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
    @Published var importing = false
    @Published var connected = UserDefaults.standard.bool(forKey: "tesla.connected")
    @Published var message: String?

    /// 개인 데이터 격리 세션 — 함수 호출 시 이 토큰으로 사용자(uid) 식별
    weak var consumer: ConsumerSession?
    private func bearer(fallback key: String) async -> String { (await consumer?.validToken()) ?? key }

    private var session: ASWebAuthenticationSession?

    func connect() async {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else {
            message = L("Supabase 미설정"); return
        }
        connecting = true; message = nil
        defer { connecting = false }

        guard let authURL = await fetchAuthURL(base: base, key: key) else {
            message = L("인증 URL을 받지 못했어요"); return
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
            message = L("연결됨")
        } else {
            message = L("연결이 취소되었어요")
        }
    }

    private func fetchAuthURL(base: URL, key: String) async -> URL? {
        var comps = URLComponents(url: base.appendingPathComponent("functions/v1/tesla-oauth"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "action", value: "authurl")]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(await bearer(fallback: key))", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = obj["url"] as? String else { return nil }
        return URL(string: s)
    }

    /// 테슬라 계정에서 차량을 가져와 새로 등록 (전기차·모델·주행거리·배터리 자동 채움).
    @discardableResult
    func importVehicle(store: VaultStore) async -> Bool {
        if !connected { await connect() }
        guard connected, let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return false }
        importing = true; defer { importing = false }

        var req = URLRequest(url: base.appendingPathComponent("functions/v1/tesla-vehicle"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(await bearer(fallback: key))", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        req.timeoutInterval = 40

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            message = L("테슬라 차량을 가져오지 못했어요"); return false
        }
        if obj["error"] != nil { message = L("테슬라 차량을 가져오지 못했어요"); return false }

        let name = (obj["name"] as? String) ?? "Tesla"
        var up = VaultStore.VehicleUpsert()
        up.name = name
        up.maker = "테슬라"
        up.model = name
        up.fuel_type = FuelType.ev.rawValue
        up.category = VehicleCategory.car.rawValue
        up.ownership = Ownership.purchase.rawValue
        if let b = obj["battery"] as? Int { up.battery = b }
        if let o = obj["odometerKm"] as? Int { up.odometer_km = o }
        do { try await store.addVehicle(up) } catch { message = L("차량 저장 실패"); return false }
        if let s = obj["status"] as? String { store.liveStatus = VehicleLiveStatus(rawValue: s) }
        message = L("테슬라 차량을 가져왔어요")
        return true
    }

    /// 배터리·주행거리 동기화 → 성공 시 차량 업데이트
    @discardableResult
    func sync(store: VaultStore) async -> Bool {
        guard connected, let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return false }
        syncing = true; defer { syncing = false }

        var req = URLRequest(url: base.appendingPathComponent("functions/v1/tesla-vehicle"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(await bearer(fallback: key))", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        req.timeoutInterval = 40

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            message = L("동기화 실패"); return false
        }

        if let err = obj["error"] as? String {
            switch err {
            case "not_connected", "reauth":
                connected = false
                UserDefaults.standard.set(false, forKey: "tesla.connected")
                message = L("재연결이 필요해요")
            case "vehicle_unavailable":
                message = L("차량이 응답하지 않아요 (잠자는 중)")
            default:
                message = L("동기화 실패")
            }
            return false
        }

        // 실시간 상태 (운행/주차/충전)
        if let s = obj["status"] as? String { store.liveStatus = VehicleLiveStatus(rawValue: s) }

        var upsert = VaultStore.VehicleUpsert()
        if let b = obj["battery"] as? Int { upsert.battery = b }
        if let o = obj["odometerKm"] as? Int { upsert.odometer_km = o }
        if upsert.battery == nil && upsert.odometer_km == nil { message = L("데이터 없음"); return false }

        try? await store.updateVehicle(upsert)
        message = L("동기화 완료")
        return true
    }

    /// 슈퍼차저 충전 이력 → 기록 자동 임포트 (신규 세션만)
    @discardableResult
    func importCharging(store: VaultStore) async -> Bool {
        if !connected { await connect() }
        guard connected, let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return false }
        importing = true; defer { importing = false }

        var req = URLRequest(url: base.appendingPathComponent("functions/v1/tesla-charging"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(await bearer(fallback: key))", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["vehicleId": store.vehicle.id.uuidString])
        req.timeoutInterval = 40

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            message = L("충전 이력 조회 실패"); return false
        }

        if let err = obj["error"] as? String {
            switch err {
            case "not_connected", "reauth":
                connected = false
                UserDefaults.standard.set(false, forKey: "tesla.connected")
                message = L("재연결이 필요해요")
            case "scope":
                message = L("테슬라 재연결 필요 (충전 이력 권한)")
            case "no_vin":
                message = L("VIN 확인 실패")
            default:
                if let st = obj["status"] as? Int {
                    message = String(format: L("충전 이력 조회 실패 (%d)"), st)
                } else {
                    message = L("충전 이력 조회 실패")
                }
            }
            return false
        }

        let imported = obj["imported"] as? Int ?? 0
        if imported > 0 { await store.load() }
        message = imported > 0
            ? String(format: L("충전 %d건 가져옴"), imported)
            : L("새 충전 내역 없음")
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
