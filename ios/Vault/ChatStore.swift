import Foundation

/// 저장되는 대화 메시지
struct StoredMsg: Codable { let role: String; let text: String }

/// 저장되는 대화 세션
struct Conversation: Codable, Identifiable {
    let id: UUID
    var title: String
    var updatedAt: Date
    var messages: [StoredMsg]
}

/// AI 어시스턴트 대화 기록 — 로컬 JSON 캐시 + Supabase 동기화(기기 간).
@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("chat_history.json")
    }()

    init() {
        loadCache()                       // 즉시 로컬 표시
        Task { await syncFromRemote() }   // 서버와 동기화
    }

    // MARK: 로컬 캐시
    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let list = try? JSONDecoder().decode([Conversation].self, from: data) else { return }
        conversations = list.sorted { $0.updatedAt > $1.updatedAt }
    }
    private func saveCache() {
        if let data = try? JSONEncoder().encode(conversations) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: Supabase
    private struct ConvDTO: Codable {
        let id: UUID; let title: String; let messages: [StoredMsg]; let updated_at: String
    }
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private func parseDate(_ s: String) -> Date {
        Self.iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? Date()
    }

    func syncFromRemote() async {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return }
        var comps = URLComponents(url: base.appendingPathComponent("rest/v1/conversations"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "select", value: "*"),
                            URLQueryItem(name: "order", value: "updated_at.desc")]
        var req = URLRequest(url: comps.url!)
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([ConvDTO].self, from: data) else { return }
        conversations = rows.map { Conversation(id: $0.id, title: $0.title, updatedAt: parseDate($0.updated_at), messages: $0.messages) }
            .sorted { $0.updatedAt > $1.updatedAt }
        saveCache()
    }

    /// 현재 대화를 저장/갱신 (로컬 즉시 + Supabase 업서트)
    func upsert(id: UUID, title: String, messages: [StoredMsg]) {
        let conv = Conversation(id: id, title: title, updatedAt: Date(), messages: messages)
        if let idx = conversations.firstIndex(where: { $0.id == id }) { conversations[idx] = conv }
        else { conversations.insert(conv, at: 0) }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        saveCache()
        Task { await pushRemote(conv) }
    }

    private func pushRemote(_ conv: Conversation) async {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return }
        var comps = URLComponents(url: base.appendingPathComponent("rest/v1/conversations"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let dto = ConvDTO(id: conv.id, title: conv.title, messages: conv.messages, updated_at: Self.iso.string(from: conv.updatedAt))
        req.httpBody = try? JSONEncoder().encode(dto)
        _ = try? await URLSession.shared.data(for: req)
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        saveCache()
        Task {
            guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return }
            var comps = URLComponents(url: base.appendingPathComponent("rest/v1/conversations"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
            var req = URLRequest(url: comps.url!)
            req.httpMethod = "DELETE"
            req.setValue(key, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}
