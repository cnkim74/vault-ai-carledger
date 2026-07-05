import Foundation
import UIKit
import AuthenticationServices

/// 테슬라 연결 + 배터리·주행거리 동기화.
/// 연결: tesla-oauth?action=authurl 로 인증 URL을 받아 ASWebAuthenticationSession 실행
///       → 테슬라 로그인 → 콜백에서 서버가 토큰 저장 → vault:// 로 복귀
/// 동기화: tesla-vehicle 호출 → 배터리·주행거리로 차량 업데이트
@MainActor
final class TeslaService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var connecting = false
    @Published var syncing = false
    @Published var connected = UserDefaults.standard.bool(forKey: "tesla.connected")
    @Published var message: String?

    private var session: ASWebAuthenticationSession?

    func connect() async {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else {
            message = "Supabase 미설정"; return
        }
        connecting = true; message = nil
        defer { connecting = false }

        guard let authURL = await fetchAuthURL(base: base, key: key) else {
            message = "인증 URL을 받지 못했어요"; return
        }

        let ok: Bool = await withCheckedContinuation { cont in
            let s = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "vault") { callback, _ in
                cont.resume(returning: callback != nil)
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            s.start()
        }

        if ok {
            connected = true
            UserDefaults.standard.set(true, forKey: "tesla.connected")
            message = "연결됨"
        } else {
            message = "연결이 취소되었어요"
        }
    }

    private func fetchAuthURL(base: URL, key: String) async -> URL? {
        var comps = URLComponents(url: base.appendingPathComponent("functions/v1/tesla-oauth"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "action", value: "authurl")]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = obj["url"] as? String else { return nil }
        return URL(string: s)
    }

    /// 배터리·주행거리 동기화 → 성공 시 차량 업데이트
    @discardableResult
    func sync(store: VaultStore) async -> Bool {
        guard connected, let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return false }
        syncing = true; defer { syncing = false }

        var req = URLRequest(url: base.appendingPathComponent("functions/v1/tesla-vehicle"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        req.timeoutInterval = 40

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            message = "동기화 실패"; return false
        }

        if let err = obj["error"] as? String {
            switch err {
            case "not_connected", "reauth":
                connected = false
                UserDefaults.standard.set(false, forKey: "tesla.connected")
                message = "재연결이 필요해요"
            case "vehicle_unavailable":
                message = "차량이 응답하지 않아요 (잠자는 중)"
            default:
                message = "동기화 실패"
            }
            return false
        }

        var upsert = VaultStore.VehicleUpsert()
        if let b = obj["battery"] as? Int { upsert.battery = b }
        if let o = obj["odometerKm"] as? Int { upsert.odometer_km = o }
        if upsert.battery == nil && upsert.odometer_km == nil { message = "데이터 없음"; return false }

        try? await store.updateVehicle(upsert)
        message = "동기화 완료"
        return true
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
