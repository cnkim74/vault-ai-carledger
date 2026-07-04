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

        guard let key = Secrets.anthropicKey, !key.isEmpty, !drives.isEmpty else { return }
        if let (km, why) = try? await predictWithClaude(vehicle: vehicle, drives: drives, placeName: placeName, key: key) {
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

    private func predictWithClaude(vehicle: Vehicle, drives: [VaultRecord], placeName: String, key: String) async throws -> (Int, String) {
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

        struct RequestBody: Encodable {
            let model = "claude-opus-4-8"
            let max_tokens = 200
            let system = """
            너는 차계부 앱의 이동거리 예측 도구다. 사용자의 최근 주행 패턴과 현재 위치를 보고 \
            이번 주(향후 7일) 예상 총 주행거리를 예측한다. 출근·통근 패턴, 요일별 주행을 고려한다. \
            반드시 아래 JSON만 출력한다: {"weekly_km":정수,"reason":"20자 이내 한국어 근거"}
            """
            let messages: [[String: String]]
        }
        let body = RequestBody(messages: [["role": "user", "content": userMsg]])

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        struct ResponseBody: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
            let stop_reason: String?
        }
        let res = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard res.stop_reason != "refusal",
              let raw = res.content.first(where: { $0.type == "text" })?.text,
              let s = raw.firstIndex(of: "{"), let e = raw.lastIndex(of: "}")
        else { throw URLError(.cannotParseResponse) }

        struct Parsed: Decodable { let weekly_km: Int; let reason: String }
        let p = try JSONDecoder().decode(Parsed.self, from: Data(String(raw[s...e]).utf8))
        return (p.weekly_km, p.reason)
    }
}
