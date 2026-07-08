import Foundation

/// Supabase Auth(GoTrue) 이메일/비밀번호 인증. Fleet(기업용) 전용 — 소비자 앱은 익명 유지.
@MainActor
final class AuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var email: String?
    @Published var userID: String?

    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?

    private let d = UserDefaults.standard
    private var authBase: URL? { Secrets.supabaseURL?.appendingPathComponent("auth/v1") }
    private var apikey: String { Secrets.supabaseKey ?? "" }

    init() { restore() }

    // MARK: 공개 API
    /// 회원가입 → (성공, 이메일확인필요) / 에러메시지
    func signUp(email: String, password: String) async -> (ok: Bool, needsConfirm: Bool, error: String?) {
        guard let url = authBase?.appendingPathComponent("signup") else { return (false, false, L("설정 오류")) }
        let (data, code) = await post(url, ["email": email, "password": password])
        guard let data else { return (false, false, L("네트워크 오류")) }
        if let s = try? JSONDecoder().decode(Session.self, from: data), let token = s.access_token {
            apply(s, token: token); return (true, false, nil)
        }
        // 세션 없이 유저만 → 이메일 확인 필요
        if code == 200, (try? JSONDecoder().decode(UserOnly.self, from: data)) != nil {
            return (true, true, nil)
        }
        return (false, false, decodeError(data))
    }

    /// 로그인
    func signIn(email: String, password: String) async -> (ok: Bool, error: String?) {
        guard var comps = authBase.map({ URLComponents(url: $0.appendingPathComponent("token"), resolvingAgainstBaseURL: false)! }) else { return (false, L("설정 오류")) }
        comps.queryItems = [.init(name: "grant_type", value: "password")]
        let (data, _) = await post(comps.url!, ["email": email, "password": password])
        guard let data else { return (false, L("네트워크 오류")) }
        if let s = try? JSONDecoder().decode(Session.self, from: data), let token = s.access_token {
            apply(s, token: token); return (true, nil)
        }
        return (false, decodeError(data))
    }

    func signOut() {
        accessToken = nil; refreshToken = nil; expiresAt = nil
        userID = nil; email = nil; isAuthenticated = false
        ["auth.access", "auth.refresh", "auth.expires", "auth.uid", "auth.email"].forEach { d.removeObject(forKey: $0) }
    }

    /// 계정 삭제 — Edge Function이 본인 데이터+인증 계정을 삭제, 성공 시 로컬 세션 정리
    func deleteAccount() async -> (ok: Bool, error: String?) {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, let token = await validToken() else {
            return (false, L("설정 오류"))
        }
        var req = URLRequest(url: base.appendingPathComponent("functions/v1/delete-account"))
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], obj["ok"] as? Bool == true else {
            return (false, L("계정 삭제에 실패했어요. 잠시 후 다시 시도해 주세요."))
        }
        signOut()
        return (true, nil)
    }

    /// 유효한 액세스 토큰 (만료 임박이면 갱신)
    func validToken() async -> String? {
        if let exp = expiresAt, exp.timeIntervalSinceNow < 60, let rt = refreshToken {
            await refresh(rt)
        }
        return accessToken
    }

    // MARK: 내부
    private func refresh(_ rt: String) async {
        guard var comps = authBase.map({ URLComponents(url: $0.appendingPathComponent("token"), resolvingAgainstBaseURL: false)! }) else { return }
        comps.queryItems = [.init(name: "grant_type", value: "refresh_token")]
        let (data, _) = await post(comps.url!, ["refresh_token": rt])
        if let data, let s = try? JSONDecoder().decode(Session.self, from: data), let token = s.access_token {
            apply(s, token: token)
        } else { signOut() }
    }

    private func apply(_ s: Session, token: String) {
        accessToken = token
        refreshToken = s.refresh_token ?? refreshToken
        expiresAt = Date().addingTimeInterval(TimeInterval(s.expires_in ?? 3600))
        userID = s.user?.id; email = s.user?.email
        isAuthenticated = true
        d.set(token, forKey: "auth.access")
        d.set(refreshToken, forKey: "auth.refresh")
        d.set(expiresAt?.timeIntervalSince1970, forKey: "auth.expires")
        d.set(userID, forKey: "auth.uid"); d.set(email, forKey: "auth.email")
    }

    private func restore() {
        guard let token = d.string(forKey: "auth.access") else { return }
        accessToken = token
        refreshToken = d.string(forKey: "auth.refresh")
        expiresAt = (d.object(forKey: "auth.expires") as? Double).map { Date(timeIntervalSince1970: $0) }
        userID = d.string(forKey: "auth.uid"); email = d.string(forKey: "auth.email")
        isAuthenticated = true
    }

    private func post(_ url: URL, _ body: [String: String]) async -> (Data?, Int) {
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue(apikey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return (nil, 0) }
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }
    private func decodeError(_ data: Data) -> String {
        if let e = try? JSONDecoder().decode(AuthErr.self, from: data) {
            return e.msg ?? e.error_description ?? e.error ?? L("인증에 실패했어요.")
        }
        return L("인증에 실패했어요.")
    }

    private struct Session: Decodable {
        let access_token: String?; let refresh_token: String?; let expires_in: Int?
        let user: U?; struct U: Decodable { let id: String; let email: String? }
    }
    private struct UserOnly: Decodable { let id: String }
    private struct AuthErr: Decodable { let msg: String?; let error_description: String?; let error: String? }
}
