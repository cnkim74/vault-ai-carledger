import Foundation
import Security

/// 소비자(개인) 데이터 격리를 위한 익명 세션.
/// 첫 실행 시 Supabase 익명 로그인 → 기기별 고유 user_id 확보.
/// vehicles/records는 이 세션 토큰으로 접근되어 owner_id(auth.uid()) 기준으로 격리된다.
/// refresh 토큰은 Keychain에 저장돼 앱 재설치에도 대부분 유지된다.
@MainActor
final class ConsumerSession: ObservableObject {
    @Published var uid: String?
    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?

    private var base: URL? { Secrets.supabaseURL }
    private var apikey: String { Secrets.supabaseKey ?? "" }
    private let d = UserDefaults.standard

    init() { restore() }

    private func restore() {
        uid = d.string(forKey: "consumer.uid")
        accessToken = d.string(forKey: "consumer.access")
        refreshToken = Keychain.get("consumer.refresh")
        if let e = d.object(forKey: "consumer.expires") as? Double { expiresAt = Date(timeIntervalSince1970: e) }
    }

    /// 앱 시작 시 호출: 세션 없으면 익명 로그인, 있으면 토큰 유효성 확보.
    func start() async {
        if refreshToken == nil { await signInAnonymously() }
        else { _ = await validToken() }
    }

    /// 유효한 액세스 토큰 (만료 임박이면 갱신, 세션 없으면 익명 로그인).
    func validToken() async -> String? {
        if let exp = expiresAt, exp.timeIntervalSinceNow < 60, let rt = refreshToken {
            await refresh(rt)
        }
        if accessToken == nil && refreshToken == nil { await signInAnonymously() }
        return accessToken
    }

    private func signInAnonymously() async {
        guard let base, !apikey.isEmpty else { return }
        var req = URLRequest(url: base.appendingPathComponent("auth/v1/signup"))
        req.httpMethod = "POST"
        req.setValue(apikey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{}".data(using: .utf8)
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            apply(data)
        }
    }

    private func refresh(_ rt: String) async {
        guard let base, !apikey.isEmpty else { return }
        var comps = URLComponents(url: base.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "grant_type", value: "refresh_token")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(apikey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": rt])
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            apply(data)
        } else {
            await signInAnonymously()   // refresh 실패 시 새 익명 세션
        }
    }

    private struct Session: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Double?
        struct U: Decodable { let id: String? }
        let user: U?
    }
    private func apply(_ data: Data) {
        guard let s = try? JSONDecoder().decode(Session.self, from: data), let at = s.access_token else { return }
        accessToken = at
        refreshToken = s.refresh_token ?? refreshToken
        uid = s.user?.id ?? uid
        let exp = Date().addingTimeInterval(s.expires_in ?? 3600)
        expiresAt = exp
        d.set(accessToken, forKey: "consumer.access")
        d.set(uid, forKey: "consumer.uid")
        d.set(exp.timeIntervalSince1970, forKey: "consumer.expires")
        if let rt = refreshToken { Keychain.set("consumer.refresh", rt) }
    }
}

/// 최소 Keychain 래퍼 (문자열 1개 저장/조회). 앱 재설치에도 유지됨.
enum Keychain {
    static func set(_ key: String, _ value: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = value.data(using: .utf8)!
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
