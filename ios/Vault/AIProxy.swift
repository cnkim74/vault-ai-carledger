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

    // 비전(이미지) 요청용 — content가 블록 배열
    private struct VisionBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Msg]
        struct Msg: Encodable { let role: String; let content: [Block] }
        struct Block: Encodable {
            let type: String
            var text: String? = nil
            var source: Source? = nil
        }
        struct Source: Encodable {
            let type = "base64"
            let media_type: String
            let data: String
        }
    }

    private struct ResponseBody: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        struct Err: Decodable { let type: String?; let message: String? }
        let content: [Block]?
        let stop_reason: String?
        let error: Err?
    }

    /// 텍스트 AI 기본 모델 — 지금은 Sonnet(비용·품질 균형). 유료 전환 시 opus로 상향 검토.
    static let defaultTextModel = "claude-sonnet-5"
    /// 이미지 인식 기본 모델 — OCR/표 추출은 Haiku로 충분(저렴).
    static let defaultVisionModel = "claude-haiku-4-5"

    /// 첫 text 블록을 반환. 미설정/거부/오류 시 nil.
    static func complete(system: String, user: String, maxTokens: Int,
                         model: String = defaultTextModel) async -> String? {
        let localizedSystem = system +
            "\n\nIMPORTANT: Regardless of any language mentioned above, write ALL human-readable text " +
            "(sentences, reasons, labels) in \(AppLocale.aiLanguageName). Keep JSON keys and numbers unchanged."
        let body = RequestBody(
            model: model, max_tokens: maxTokens, system: localizedSystem,
            messages: [.init(role: "user", content: user)]
        )
        guard let data = try? JSONEncoder().encode(body) else { return nil }
        return await post(data)
    }

    /// 이미지(영수증·충전 화면 등) + 프롬프트 → 첫 text 블록 반환.
    static func completeWithImage(system: String, prompt: String, jpegBase64: String,
                                  mediaType: String = "image/jpeg", maxTokens: Int = 512,
                                  model: String = defaultVisionModel) async -> String? {
        let msg = VisionBody.Msg(role: "user", content: [
            VisionBody.Block(type: "image", source: .init(media_type: mediaType, data: jpegBase64)),
            VisionBody.Block(type: "text", text: prompt),
        ])
        let body = VisionBody(model: model, max_tokens: maxTokens, system: system, messages: [msg])
        guard let data = try? JSONEncoder().encode(body) else { return nil }
        return await post(data)
    }

    /// 공통 HTTP 전송 + 응답 파싱.
    private static func post(_ data: Data) async -> String? {
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
            if res.error != nil { return nil }
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
