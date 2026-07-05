import Foundation

/// 기록 데이터 기반 절약/관리 인사이트를 Claude로 생성한다.
/// AIProxy(직접 키 또는 Edge Function)가 미설정이면 기본 문구를 유지한다.
@MainActor
final class InsightService: ObservableObject {
    @Published var tip: String?
    @Published var loading = false

    private static let system = """
    너는 차계부 앱 VAULT의 AI 비서다. 사용자의 차량 정보와 최근 기록을 보고 \
    비용 절약이나 차량 관리에 실질적으로 도움이 되는 인사이트를 정확히 한 문장의 한국어로 제안한다. \
    가능하면 구체적인 숫자(금액·거리·비율)를 포함한다. 인사말·설명 없이 그 한 문장만 출력한다.
    """

    func generate(vehicle: Vehicle, records: [VaultRecord]) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }

        let context = Self.buildContext(vehicle: vehicle, records: records)
        if let text = await AIProxy.complete(system: Self.system, user: context, maxTokens: 300),
           !text.isEmpty {
            tip = text
        }
    }

    private static func buildContext(vehicle: Vehicle, records: [VaultRecord]) -> String {
        let df = DateFormatter()
        df.dateFormat = "M/d HH:mm"

        var lines: [String] = []
        lines.append("차량: \(vehicle.name) (\(vehicle.fuelType), \(vehicle.ownership.label))")
        lines.append("누적 주행: \(vehicle.odometerKm)km")
        if let limit = vehicle.leaseLimitKm {
            lines.append("약정거리: \(vehicle.leaseDriven)/\(limit)km" + (vehicle.contractEnd.map { " (계약 종료 \($0))" } ?? ""))
        }
        if let fee = vehicle.monthlyFeeWon {
            lines.append("월 납입금: \(fee)원")
        }
        lines.append("")
        lines.append("최근 기록:")
        for r in records.prefix(10) {
            var parts = ["[\(df.string(from: r.occurredAt))] \(r.title)"]
            if let a = r.amountWon { parts.append("\(a)원") }
            if let d = r.distanceKm { parts.append("\(d)km") }
            if let m = r.durationMin { parts.append("\(m)분") }
            if let l = r.location { parts.append(l) }
            if let t = r.tag { parts.append(t) }
            lines.append(parts.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }
}
