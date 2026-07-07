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

/// AI 어시스턴트 대화 기록 — 로컬 JSON 파일에 영속화.
@MainActor
final class ChatStore: ObservableObject {
    @Published var conversations: [Conversation] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("chat_history.json")
    }()

    init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Conversation].self, from: data) else { return }
        conversations = list.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(conversations) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 현재 대화를 저장/갱신
    func upsert(id: UUID, title: String, messages: [StoredMsg]) {
        let conv = Conversation(id: id, title: title, updatedAt: Date(), messages: messages)
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx] = conv
        } else {
            conversations.insert(conv, at: 0)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        persist()
    }
}
