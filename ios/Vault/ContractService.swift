import Foundation
import PDFKit

/// 계약서 PDF에서 계약일·약정일·약정거리·월납입금을 추출한다.
/// 1) PDFKit으로 텍스트 추출 → 2) Claude API로 구조화 파싱(JSON).
/// Secrets.anthropicKey가 없으면 정규식 기반 로컬 파서로 폴백.
struct ContractInfo {
    var contractStart: String?   // yyyy-MM-dd
    var contractEnd: String?     // yyyy-MM-dd
    var leaseLimitKm: Int?
    var monthlyFeeWon: Int?
    var maker: String?
    var model: String?
    var plate: String?
}

enum ContractError: LocalizedError {
    case unreadable
    case empty
    var errorDescription: String? {
        switch self {
        case .unreadable: return "PDF를 읽을 수 없어요."
        case .empty: return "PDF에서 텍스트를 찾지 못했어요. (스캔 이미지 PDF는 지원되지 않아요)"
        }
    }
}

@MainActor
final class ContractService: ObservableObject {
    @Published var parsing = false

    func parse(url: URL) async throws -> ContractInfo {
        parsing = true
        defer { parsing = false }

        // 보안 스코프 리소스 접근 (파일 선택기 경유)
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: url) else { throw ContractError.unreadable }
        var text = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let s = page.string { text += s + "\n" }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ContractError.empty }

        if let key = Secrets.anthropicKey, !key.isEmpty,
           let info = try? await parseWithClaude(text: text, key: key) {
            return info
        }
        return Self.parseLocally(text: text)
    }

    // ── Claude 파싱 (구조화 출력) ──────────────────────

    private func parseWithClaude(text: String, key: String) async throws -> ContractInfo {
        let clipped = String(text.prefix(8000))

        struct RequestBody: Encodable {
            let model = "claude-opus-4-8"
            let max_tokens = 500
            let system = """
            너는 자동차 리스/렌트 계약서에서 핵심 정보를 추출하는 도구다. \
            아래 계약서 텍스트에서 다음을 찾아 JSON만 출력한다(설명 금지):
            {"contract_start":"YYYY-MM-DD 또는 null","contract_end":"YYYY-MM-DD 또는 null",\
            "lease_limit_km":정수 또는 null,"monthly_fee_won":정수 또는 null,\
            "maker":"제조사 또는 null","model":"모델명 또는 null","plate":"차량번호 또는 null"}
            약정거리가 연간이면 계약기간(년)을 곱해 총 약정거리로 환산한다. \
            금액·거리의 콤마와 단위는 제거하고 숫자만 넣는다.
            """
            let messages: [[String: String]]
        }
        let body = RequestBody(messages: [["role": "user", "content": clipped]])

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ContractError.unreadable
        }
        struct ResponseBody: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        let res = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let raw = res.content.first(where: { $0.type == "text" })?.text else {
            throw ContractError.unreadable
        }
        // JSON 부분만 추출
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") else {
            throw ContractError.unreadable
        }
        let json = String(raw[start...end])

        struct Parsed: Decodable {
            let contract_start: String?
            let contract_end: String?
            let lease_limit_km: Int?
            let monthly_fee_won: Int?
            let maker: String?
            let model: String?
            let plate: String?
        }
        let p = try JSONDecoder().decode(Parsed.self, from: Data(json.utf8))
        return ContractInfo(
            contractStart: p.contract_start,
            contractEnd: p.contract_end,
            leaseLimitKm: p.lease_limit_km,
            monthlyFeeWon: p.monthly_fee_won,
            maker: p.maker,
            model: p.model,
            plate: p.plate
        )
    }

    // ── 로컬 정규식 폴백 ───────────────────────────────

    private static func parseLocally(text: String) -> ContractInfo {
        var info = ContractInfo()
        let dates = matchDates(in: text)
        if dates.count >= 2 {
            info.contractStart = dates.first
            info.contractEnd = dates.last
        } else if let d = dates.first {
            info.contractStart = d
        }
        // 약정거리: "약정거리 20,000km" / "연간 20000 km"
        if let km = firstInt(pattern: #"약정\s*(?:거리|주행거리)[^0-9]{0,10}([0-9,]{3,})"#, in: text) {
            info.leaseLimitKm = km
        }
        // 월 납입금: "월 리스료 890,000원" / "월 납입금 890000"
        if let fee = firstInt(pattern: #"월\s*(?:리스료|렌트료|납입금|이용료)[^0-9]{0,10}([0-9,]{4,})"#, in: text) {
            info.monthlyFeeWon = fee
        }
        // 차량번호: "12가 3456" / "123가 4567"
        if let m = firstMatch(pattern: #"\b(\d{2,3}[가-힣]\s?\d{4})\b"#, in: text) {
            info.plate = m.replacingOccurrences(of: " ", with: " ")
        }
        return info
    }

    private static func matchDates(in text: String) -> [String] {
        // 2024-07-01 / 2024.07.01 / 2024년 7월 1일
        var out: [String] = []
        let patterns = [
            #"(\d{4})[.\-/년]\s?(\d{1,2})[.\-/월]\s?(\d{1,2})"#
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let y = ns.substring(with: m.range(at: 1))
                let mo = ns.substring(with: m.range(at: 2))
                let d = ns.substring(with: m.range(at: 3))
                out.append(String(format: "%@-%02d-%02d", y, Int(mo) ?? 0, Int(d) ?? 0))
            }
        }
        return out
    }

    private static func firstInt(pattern: String, in text: String) -> Int? {
        guard let s = firstMatch(pattern: pattern, in: text, group: 1) else { return nil }
        return Int(s.replacingOccurrences(of: ",", with: ""))
    }

    private static func firstMatch(pattern: String, in text: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group else { return nil }
        return ns.substring(with: m.range(at: group))
    }
}
