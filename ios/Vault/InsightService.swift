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
    가능하면 구체적인 숫자(금액·거리·비율)를 포함한다. \
    금액·거리 등 네 자리 이상 숫자는 천단위 쉼표를 넣는다 (예: 38,200원, 12,000km). 단 연도에는 넣지 않는다. \
    중요: 잔여 계약기간·잔여 거리·적정 대비·만료 예상 등의 수치는 아래 컨텍스트에 계산되어 제공되므로, \
    날짜나 기간을 스스로 계산하지 말고 제공된 값을 그대로 사용한다. 제공되지 않은 값은 지어내지 않는다. \
    인사말·설명 없이 그 한 문장만 출력한다.
    """

    func generate(vehicle: Vehicle, records: [VaultRecord]) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }

        let context = Self.buildContext(vehicle: vehicle, records: records)
        if let text = await AIProxy.complete(system: Self.system, user: context, maxTokens: 300),
           !text.isEmpty {
            tip = groupInlineNumbers(text)   // AI 출력 숫자에 천단위 쉼표 보정
        }
    }

    private static func buildContext(vehicle: Vehicle, records: [VaultRecord]) -> String {
        let df = DateFormatter()
        df.dateFormat = "M/d HH:mm"
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"

        var lines: [String] = []
        lines.append("오늘: \(dayFmt.string(from: Date()))")
        lines.append("차량: \(vehicle.name) (\(vehicle.fuelType), \(vehicle.ownership.label))")
        lines.append("누적 주행: \(vehicle.odometerKm)km")

        // 약정거리 관련 수치는 코드에서 정확히 계산해 넘긴다 (AI 재계산 방지)
        if let p = vehicle.leaseProjection() {
            let remainKm = max(0, p.limitKm - p.drivenKm)
            let dr = max(0, p.daysRemaining)
            let yrs = dr / 365, mos = (dr % 365) / 30
            let period = yrs > 0 ? "약 \(yrs)년 \(mos)개월" : "약 \(mos)개월"
            lines.append("약정거리: \(p.drivenKm)/\(p.limitKm)km (계약 시작 후 주행)")
            lines.append("잔여 약정거리: \(remainKm)km")
            lines.append("잔여 계약기간: \(dr)일 (\(period))" + (vehicle.contractEnd.map { ", 종료 \($0)" } ?? ""))
            lines.append("오늘 기준 적정 대비: \(p.paceRatioPct)% (\(p.isOverPace ? "초과 페이스" : "여유 페이스"))")
            let over = p.overageKm > 0
            lines.append("만료 시 예상 총주행: \(p.projectedTotalKm)km (" + (over ? "예상 초과 \(p.overageKm)km" : "예상 여유 \(-p.overageKm)km") + ")")
        } else if let limit = vehicle.leaseLimitKm {
            lines.append("약정거리: \(vehicle.leaseDriven)/\(limit)km")
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
