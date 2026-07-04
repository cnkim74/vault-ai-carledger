import Foundation

/// 최근 주행 기록 + 현재 위치를 바탕으로 예상 이동거리를 산출한다.
/// Claude 키가 있으면 AI 예측, 없으면 기록 기반 통계 추정.
@MainActor
final class PredictionService: ObservableObject {
    @Published var weeklyKm: Int?
    @Published var reason: String?
    @Published var isAI = false

    func predict(vehicle: Vehicle, records: [VaultRecord], placeName: String) async {
        let drives = records.filter { $0.kind == .drive && $0.distanceKm != nil }

        // 로컬 통계 추정: 최근 주행 평균 × 주간 빈도 근사
        let localEstimate = Self.heuristicWeeklyKm(drives: drives)
        weeklyKm = localEstimate
        reason = "최근 주행 기록 기반 추정"
        isAI = false

        guard !drives.isEmpty else { return }
        if let (km, why) = await predictWithClaude(vehicle: vehicle, drives: drives, placeName: placeName) {
            weeklyKm = km
            reason = why
            isAI = true
        }
    }

    private static func heuristicWeeklyKm(drives: [VaultRecord]) -> Int? {
        guard !drives.isEmpty else { return nil }
        let sorted = drives.sorted { $0.occurredAt < $1.occurredAt }
        let totalKm = drives.compactMap { $0.distanceKm }.reduce(0, +)
        guard let first = sorted.first?.occurredAt, let last = sorted.last?.occurredAt else { return nil }
        let days = max(1.0, last.timeIntervalSince(first) / 86400)
        // 기록이 하루 안에 몰려 있으면 그날 합계를 일평균으로 간주
        let daily = days < 1.5 ? totalKm : totalKm / days
        return Int((daily * 7).rounded())
    }

    private static let system = """
    너는 차계부 앱의 이동거리 예측 도구다. 사용자의 최근 주행 패턴과 현재 위치를 보고 \
    이번 주(향후 7일) 예상 총 주행거리를 예측한다. 출근·통근 패턴, 요일별 주행을 고려한다. \
    반드시 아래 JSON만 출력한다: {"weekly_km":정수,"reason":"20자 이내 한국어 근거"}
    """

    private func predictWithClaude(vehicle: Vehicle, drives: [VaultRecord], placeName: String) async -> (Int, String)? {
        let df = DateFormatter()
        df.dateFormat = "M/d(E) HH:mm"
        df.locale = Locale(identifier: "ko_KR")
        let lines = drives.prefix(12).map { r -> String in
            var s = "\(df.string(from: r.occurredAt)) \(r.title)"
            if let d = r.distanceKm { s += " \(d)km" }
            if let t = r.tag { s += " (\(t))" }
            return s
        }.joined(separator: "\n")

        let userMsg = """
        현재 위치: \(placeName)
        차량: \(vehicle.name)
        최근 주행 기록:
        \(lines)
        """

        guard let text = await AIProxy.complete(system: Self.system, user: userMsg, maxTokens: 200),
              let json = AIProxy.extractJSON(text) else { return nil }

        struct Parsed: Decodable { let weekly_km: Int; let reason: String }
        guard let p = try? JSONDecoder().decode(Parsed.self, from: json) else { return nil }
        return (p.weekly_km, p.reason)
    }
}
