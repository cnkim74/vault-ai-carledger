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

    /// 차종별 추정 기준 (자동차 vs 바이크/스쿠터)
    private static func system(for vehicle: Vehicle) -> String {
        let base = """
        아래 JSON만 출력한다(원화 만원 단위 정수). 실거래가가 아닌 추정치이므로 합리적 범위를 제시한다: \
        {"low":정수,"avg":정수,"high":정수,"note":"20자 이내 핵심 근거"}
        """
        switch vehicle.vehicleCategory {
        case .motorcycle, .scooter:
            return """
            너는 한국 중고 이륜차(오토바이·스쿠터) 시세 추정 전문가다. 추정 시 다음을 반영한다: \
            배기량(모델명으로 유추)·모델 인기와 유통 물량·연식·주행거리(이륜차는 자동차보다 주행 영향이 큼)·관리 상태. \
            수입/한정 모델이나 유통이 적은 모델은 범위를 넉넉히 잡는다. 신차가보다 크게 벗어나지 않게 한다.
            \(base)
            """
        case .car:
            return """
            너는 한국 중고차 시세 추정 전문가다. 추정 시 다음을 반영한다: \
            제조사·모델 인기와 감가 특성·연식·주행거리·연료 타입(전기차는 배터리 우려로 감가 큼)·국내 유통 물량. \
            신차가와 감가 곡선을 벗어나지 않는 합리적 범위를 제시한다.
            \(base)
            """
        }
    }

    func fetch(vehicle: Vehicle) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }

        let isBike = vehicle.isBike
        var lines = ["차종: \(vehicle.vehicleCategory.label)"]
        if let mk = vehicle.maker { lines.append(isBike ? "브랜드: \(mk)" : "제조사: \(mk)") }
        lines.append("모델: \(vehicle.model ?? vehicle.name)")
        if let y = vehicle.year { lines.append("연식: \(y)년") }
        if !isBike { lines.append("연료: \(vehicle.fuelType)") }   // 이륜차는 연료 영향 미미
        lines.append("누적 주행: \(vehicle.odometerKm)km")
        if isBike { lines.append("※ 이륜차는 주행거리·배기량·모델 인기를 특히 크게 반영") }
        let ctx = lines.joined(separator: "\n")

        guard let text = await AIProxy.complete(system: Self.system(for: vehicle), user: ctx, maxTokens: 220),
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
