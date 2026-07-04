import Foundation

/// Claude API로 실제 기록 데이터 기반 절약/관리 인사이트를 생성한다.
/// Secrets.anthropicKey가 없으면 아무것도 하지 않는다 (화면은 기본 문구 유지).
///
/// Swift용 공식 SDK가 없어 Messages API를 raw HTTP로 호출한다.
/// https://platform.claude.com/docs — POST /v1/messages
@MainActor
final class InsightService: ObservableObject {
    @Published var tip: String?
    @Published var loading = false

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func generate(vehicle: Vehicle, records: [VaultRecord]) async {
        guard let key = Secrets.anthropicKey, !key.isEmpty else { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }

        let context = Self.buildContext(vehicle: vehicle, records: records)

        struct RequestBody: Encodable {
            let model: String
            let max_tokens: Int
            let system: String
            let messages: [Message]
            struct Message: Encodable {
                let role: String
                let content: String
            }
        }

        let body = RequestBody(
            model: "claude-opus-4-8",
            max_tokens: 300,
            system: """
            너는 차계부 앱 VAULT의 AI 비서다. 사용자의 차량 정보와 최근 기록을 보고 \
            비용 절약이나 차량 관리에 실질적으로 도움이 되는 인사이트를 정확히 한 문장의 한국어로 제안한다. \
            가능하면 구체적인 숫자(금액·거리·비율)를 포함한다. 인사말·설명 없이 그 한 문장만 출력한다.
            """,
            messages: [.init(role: "user", content: context)]
        )

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60

        do {
            req.httpBody = try JSONEncoder().encode(body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                print("[InsightService] HTTP error: \(String(data: data, encoding: .utf8) ?? "")")
                return
            }

            struct ResponseBody: Decodable {
                struct Block: Decodable {
                    let type: String
                    let text: String?
                }
                let content: [Block]
                let stop_reason: String?
            }
            let res = try JSONDecoder().decode(ResponseBody.self, from: data)

            // refusal 등 비정상 종료 시 기본 문구 유지
            guard res.stop_reason != "refusal" else { return }
            if let text = res.content.first(where: { $0.type == "text" })?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty {
                tip = text
            }
        } catch {
            print("[InsightService] request failed: \(error)")
        }
    }

    private static func buildContext(vehicle: Vehicle, records: [VaultRecord]) -> String {
        let df = DateFormatter()
        df.dateFormat = "M/d HH:mm"

        var lines: [String] = []
        lines.append("차량: \(vehicle.name) (\(vehicle.fuelType), \(vehicle.ownership.label))")
        lines.append("누적 주행: \(vehicle.odometerKm)km")
        if let limit = vehicle.leaseLimitKm, let driven = vehicle.leaseDrivenKm {
            lines.append("약정거리: \(driven)/\(limit)km" + (vehicle.contractEnd.map { " (계약 종료 \($0))" } ?? ""))
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
