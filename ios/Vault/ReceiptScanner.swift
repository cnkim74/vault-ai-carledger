import UIKit

/// 영수증·충전 화면 사진에서 추출한 기록 정보.
struct ScannedRecord {
    var kind: RecordKind
    var title: String?
    var amountWon: Int?
    var quantity: Double?      // 충전 kWh 또는 주유 L
    var distanceKm: Double?
    var location: String?
}

/// 사진 → Claude 비전 → 기록 필드 자동 추출.
@MainActor
final class ReceiptScanner: ObservableObject {
    @Published var scanning = false
    @Published var error: String?

    private static let system = """
    You extract structured vehicle expense data from a photo of a receipt, \
    charging-station screen, or fuel pump. Return ONLY a JSON object, no prose.
    Schema:
    {
      "kind": "charge" | "fuel" | "maintenance" | "drive",
      "amount_won": integer or null,   // total paid in KRW
      "quantity": number or null,      // kWh if charge, liters if fuel
      "distance_km": number or null,
      "location": string or null,      // station/shop name
      "title": string or null          // short label
    }
    Rules: infer kind from context (EV charger→charge, gas pump→fuel, repair→maintenance).
    Numbers only for numeric fields (no units, no commas). If unreadable, use null.
    """

    /// 이미지에서 기록 필드 추출. 실패 시 nil.
    func scan(_ image: UIImage) async -> ScannedRecord? {
        scanning = true; error = nil
        defer { scanning = false }

        guard let base64 = Self.downscaledJPEGBase64(image) else {
            error = L("이미지를 처리할 수 없어요"); return nil
        }
        let prompt = "Extract the vehicle expense from this image as JSON per the schema."
        guard let text = await AIProxy.completeWithImage(system: Self.system, prompt: prompt,
                                                         jpegBase64: base64, maxTokens: 400),
              let data = AIProxy.extractJSON(text),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            error = L("인식에 실패했어요. 다시 시도하거나 직접 입력해 주세요."); return nil
        }

        let kindRaw = (obj["kind"] as? String) ?? "fuel"
        let kind = RecordKind(rawValue: kindRaw) ?? .fuel
        func num(_ v: Any?) -> Double? {
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: "")) }
            return nil
        }
        let scanned = ScannedRecord(
            kind: kind,
            title: (obj["title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            amountWon: num(obj["amount_won"]).map { Int($0) },
            quantity: num(obj["quantity"]),
            distanceKm: num(obj["distance_km"]),
            location: (obj["location"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
        // 아무것도 못 뽑았으면 실패로 간주
        if scanned.amountWon == nil && scanned.quantity == nil && scanned.location == nil && scanned.title == nil {
            error = L("인식에 실패했어요. 다시 시도하거나 직접 입력해 주세요."); return nil
        }
        return scanned
    }

    /// 긴 변 1280px로 축소 + JPEG 0.6 → Base64. 페이로드·비용 절감.
    private static func downscaledJPEGBase64(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 1280
        let w = image.size.width, h = image.size.height
        let scale = min(1, maxSide / max(w, h))
        let target = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.6) else { return nil }
        return jpeg.base64EncodedString()
    }
}
