import Foundation

/// Claude 호출 단일 창구.
/// - Secrets.anthropicKey가 있으면 api.anthropic.com 직접 호출 (로컬 전용)
/// - 없으면 Supabase Edge Function `ai-proxy` 경유 (키는 서버 시크릿에만 보관)
/// 미설정·거부·오류 시 nil을 반환해 각 기능이 기본값으로 폴백하도록 한다.
enum AIProxy {
    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Msg]
        struct Msg: Encodable { let role: String; let content: String }
    }

    private struct ResponseBody: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        struct Err: Decodable { let type: String?; let message: String? }
        let content: [Block]?
        let stop_reason: String?
        let error: Err?
    }

    /// 첫 text 블록을 반환. 미설정/거부/오류 시 nil.
    static func complete(system: String, user: String, maxTokens: Int,
                         model: String = "claude-opus-4-8") async -> String? {
        let body = RequestBody(
            model: model, max_tokens: maxTokens, system: system,
            messages: [.init(role: "user", content: user)]
        )
        guard let data = try? JSONEncoder().encode(body) else { return nil }

        var req: URLRequest
        if let key = Secrets.anthropicKey, !key.isEmpty {
            req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if let base = Secrets.supabaseURL, let anon = Secrets.supabaseKey, !anon.isEmpty {
            req = URLRequest(url: base.appendingPathComponent("functions/v1/ai-proxy"))
            req.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        } else {
            return nil
        }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        req.httpBody = data

        do {
            let (respData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let res = try JSONDecoder().decode(ResponseBody.self, from: respData)
            if res.error != nil { return nil }              // no_key 등
            if res.stop_reason == "refusal" { return nil }
            return res.content?.first(where: { $0.type == "text" })?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// 응답 텍스트에서 첫 JSON 객체 부분만 추출.
    static func extractJSON(_ text: String) -> Data? {
        guard let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}") else { return nil }
        return Data(text[s...e].utf8)
    }
}
