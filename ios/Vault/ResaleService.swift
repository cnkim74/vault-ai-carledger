import Foundation

/// 차량 정보 기반 중고 시세 AI 추정 (프리미엄).
/// 실시간 시장 데이터가 아닌 추정치 — 실제 거래가는 엔카·KB차차차 등에서 확인.
struct ResaleEstimate {
    var low: Int       // 만원
    var avg: Int
    var high: Int
    var note: String?
}

@MainActor
final class ResaleService: ObservableObject {
    @Published var loading = false
    @Published var estimate: ResaleEstimate?
    @Published var error: String?

    /// 차량 전환 시 이전 결과 초기화
    func reset() {
        estimate = nil
        error = nil
    }

    private static let system = """
    너는 한국 중고차 시세 추정 도우미다. 주어진 차량 정보로 한국 중고차 시장 기준 \
    예상 시세를 추정한다. 실거래가가 아닌 추정치이므로 합리적 범위를 제시한다. \
    아래 JSON만 출력한다(만원 단위 정수): \
    {"low":정수,"avg":정수,"high":정수,"note":"20자 이내 근거"}
    """

    func fetch(vehicle: Vehicle) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }

        var lines = ["차종: \(vehicle.vehicleCategory.label)"]
        if let mk = vehicle.maker { lines.append("제조사: \(mk)") }
        lines.append("모델: \(vehicle.model ?? vehicle.name)")
        if let y = vehicle.year { lines.append("연식: \(y)년") }
        lines.append("연료: \(vehicle.fuelType)")
        lines.append("누적 주행: \(vehicle.odometerKm)km")
        let ctx = lines.joined(separator: "\n")

        guard let text = await AIProxy.complete(system: Self.system, user: ctx, maxTokens: 200),
              let data = AIProxy.extractJSON(text),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            error = L("시세를 추정하지 못했어요. 잠시 후 다시 시도해 주세요."); return
        }
        func i(_ k: String) -> Int? {
            if let n = obj[k] as? Int { return n }
            if let d = obj[k] as? Double { return Int(d) }
            if let s = obj[k] as? String { return Int(s.replacingOccurrences(of: ",", with: "")) }
            return nil
        }
        guard let low = i("low"), let avg = i("avg"), let high = i("high") else {
            error = L("시세를 추정하지 못했어요. 잠시 후 다시 시도해 주세요."); return
        }
        estimate = ResaleEstimate(low: low, avg: avg, high: high, note: obj["note"] as? String)
    }
}
