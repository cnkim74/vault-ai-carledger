import Foundation
import UserNotifications

/// 관리자 상태 + 미처리 문의 개수. 앱 열 때/포그라운드 복귀 시 갱신하여
/// 앱 아이콘 배지 + 프로필 배지 + (증가 시) 로컬 알림을 제공.
@MainActor
final class AdminStore: ObservableObject {
    @Published var isAdmin = false
    @Published var pendingCount = 0
    private let seenKey = "admin.inbox.seenPending"

    func refresh(auth: AuthService) async {
        guard auth.isAuthenticated,
              let base = Secrets.supabaseURL, let key = Secrets.supabaseKey,
              let token = await auth.validToken() else {
            isAdmin = false; pendingCount = 0; await setBadge(0); return
        }
        isAdmin = await fetchIsAdmin(base: base, key: key, token: token)
        guard isAdmin else { pendingCount = 0; await setBadge(0); return }

        let count = await fetchPending(base: base, key: key, token: token)
        let seen = UserDefaults.standard.integer(forKey: seenKey)
        pendingCount = count
        await setBadge(count)
        if count > seen { await notify(new: count - seen) }
        UserDefaults.standard.set(count, forKey: seenKey)
    }

    private func get(_ path: String, query: [URLQueryItem], base: URL, key: String, token: String) async -> [[String: AnyDecodable]]? {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "apikey"); req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode([[String: AnyDecodable]].self, from: data)
    }

    private func fetchIsAdmin(base: URL, key: String, token: String) async -> Bool {
        let rows = await get("rest/v1/admin_emails",
            query: [.init(name: "select", value: "email"), .init(name: "limit", value: "1")],
            base: base, key: key, token: token)
        return (rows?.isEmpty == false)
    }
    private func fetchPending(base: URL, key: String, token: String) async -> Int {
        let rows = await get("rest/v1/inquiries",
            query: [.init(name: "select", value: "id"), .init(name: "handled", value: "eq.false")],
            base: base, key: key, token: token)
        return rows?.count ?? 0
    }

    private func setBadge(_ n: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(n)
    }
    private func notify(new: Int) async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        let c = UNMutableNotificationContent()
        c.title = "Wheelet"
        c.body = String(format: L("새 문의 %d건이 있어요."), new)
        c.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "admin-inbox-new", content: c,
                                  trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
    }
}

/// JSON의 임의 값을 무시하고 디코딩만 성공시키는 헬퍼(행 개수만 필요할 때).
struct AnyDecodable: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if (try? c.decode(String.self)) != nil { return }
        if (try? c.decode(Int.self)) != nil { return }
        if (try? c.decode(Double.self)) != nil { return }
        if (try? c.decode(Bool.self)) != nil { return }
        _ = try? c.decodeNil()
    }
}
