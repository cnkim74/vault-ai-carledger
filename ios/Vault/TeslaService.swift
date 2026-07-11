import Foundation
import UIKit
import AuthenticationServices
import CoreLocation
import Contacts

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

    // 주변 슈퍼차저
    struct NearbyCharger: Identifiable {
        let id = UUID()
        let name: String
        let distanceKm: Double?
        let availableStalls: Int?
        let totalStalls: Int?
        let closed: Bool
        let lat: Double?
        let long: Double?
    }
    @Published var nearby: [NearbyCharger] = []
    @Published var nearbyLoading = false
    @Published var nearbyError: String?

    // 차량 현재 위치
    struct VehicleLocation { let lat: Double; let long: Double; let name: String?; let status: String? }
    @Published var location: VehicleLocation?
    @Published var locationLoading = false
    @Published var locationError: String?
    @Published var locationNeedsReconnect = false

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
        // 현재 위치 → 주소 (위치 권한 있을 때만 좌표가 옴)
        if let lat = (obj["lat"] as? NSNumber)?.doubleValue, let long = (obj["long"] as? NSNumber)?.doubleValue,
           let addr = await Self.reverseGeocode(lat: lat, long: long) {
            store.liveLocationAddress = addr
        }

        var upsert = VaultStore.VehicleUpsert()
        if let b = obj["battery"] as? Int { upsert.battery = b }
        if let o = obj["odometerKm"] as? Int { upsert.odometer_km = o }
        if upsert.battery == nil && upsert.odometer_km == nil { message = L("데이터 없음"); return false }

        try? await store.updateVehicle(upsert)
        message = L("동기화 완료")
        return true
    }

    /// 차량 기준 주변 슈퍼차저 조회 (vehicle_device_data 권한)
    func loadNearby() async {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return }
        nearbyLoading = true; nearbyError = nil; defer { nearbyLoading = false }

        var req = URLRequest(url: base.appendingPathComponent("functions/v1/tesla-nearby"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(await bearer(fallback: key))", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        req.timeoutInterval = 45

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            nearbyError = L("주변 충전소를 불러오지 못했어요"); return
        }
        if let err = obj["error"] as? String {
            nearbyError = err == "vehicle_unavailable"
                ? L("차량이 응답하지 않아요 (잠자는 중)")
                : (err == "not_connected" ? L("테슬라 미연결") : L("주변 충전소를 불러오지 못했어요"))
            return
        }
        let arr = (obj["superchargers"] as? [[String: Any]]) ?? []
        nearby = arr.map { s in
            NearbyCharger(
                name: s["name"] as? String ?? "Supercharger",
                distanceKm: (s["distanceKm"] as? NSNumber)?.doubleValue,
                availableStalls: (s["availableStalls"] as? NSNumber)?.intValue,
                totalStalls: (s["totalStalls"] as? NSNumber)?.intValue,
                closed: (s["closed"] as? Bool) ?? false,
                lat: (s["lat"] as? NSNumber)?.doubleValue,
                long: (s["long"] as? NSNumber)?.doubleValue
            )
        }
    }

    /// 차량 현재 위치 조회 (vehicle_location 권한 필요). 좌표 없으면 재연결 안내.
    func loadLocation() async {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return }
        locationLoading = true; locationError = nil; locationNeedsReconnect = false
        defer { locationLoading = false }

        var req = URLRequest(url: base.appendingPathComponent("functions/v1/tesla-vehicle"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(await bearer(fallback: key))", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        req.timeoutInterval = 45

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            locationError = L("차량 위치를 불러오지 못했어요"); return
        }
        if let err = obj["error"] as? String {
            locationError = err == "vehicle_unavailable"
                ? L("차량이 응답하지 않아요 (잠자는 중)")
                : (err == "not_connected" ? L("테슬라 미연결") : L("차량 위치를 불러오지 못했어요"))
            return
        }
        let lat = (obj["lat"] as? NSNumber)?.doubleValue
        let long = (obj["long"] as? NSNumber)?.doubleValue
        if let lat, let long {
            location = VehicleLocation(lat: lat, long: long,
                                       name: obj["name"] as? String,
                                       status: obj["status"] as? String)
        } else {
            // 좌표가 비면 위치 권한(vehicle_location) 미부여 → 재연결 필요
            locationNeedsReconnect = true
            locationError = L("위치 권한이 없어요. 테슬라를 다시 연결해 주세요.")
        }
    }

    /// 슈퍼차저 충전 이력 → 기록 자동 임포트 (신규 세션만)
    @discardableResult
    func importCharging(store: VaultStore, retried: Bool = false) async -> Bool {
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
            let status = obj["status"] as? Int
            let serverMsg = (obj["message"] as? String) ?? ""
            let tail = serverMsg.isEmpty ? "" : "\n\(serverMsg.prefix(140))"
            switch err {
            case "not_connected", "reauth":
                // 토큰 만료·갱신 실패 → 자동으로 다시 로그인 후 1회만 재시도 (무한 루프 방지)
                connected = false
                UserDefaults.standard.set(false, forKey: "tesla.connected")
                if !retried {
                    message = L("테슬라 다시 로그인 중…")
                    await connect()
                    if connected { return await importCharging(store: store, retried: true) }
                }
                message = L("테슬라 로그인이 필요해요")
            case "scope":
                // 재로그인으론 안 풀림(파트너 앱 권한/충전 API 미승인) → 루프 중단, 원인 노출
                message = L("충전 이력 권한이 없어요") + (status.map { " (\($0))" } ?? "") + tail
            case "no_vin":
                message = L("VIN 확인 실패")
            default:
                message = L("충전 이력 조회 실패") + (status.map { " (\($0))" } ?? "") + tail
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

    /// 위경도 → 한글 주소 (도로명·건물번호까지 최대한 상세). 예: "안동시 경동로 400"
    static func reverseGeocode(lat: Double, long: Double) async -> String? {
        let geo = CLGeocoder()
        guard let pm = try? await geo.reverseGeocodeLocation(
            CLLocation(latitude: lat, longitude: long),
            preferredLocale: Locale(identifier: "ko_KR")).first else { return nil }

        // 시/군/구
        let city = [pm.locality, pm.subAdministrativeArea, pm.administrativeArea]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.first
        // 도로명(+건물번호) 우선, 없으면 우편주소 street, 그것도 없으면 동/도로명 조합
        var street = ""
        if let t = pm.thoroughfare, !t.isEmpty {
            street = t + (pm.subThoroughfare.map { " \($0)" } ?? "")
        } else if let s = pm.postalAddress?.street, !s.isEmpty {
            street = s
        } else {
            street = [pm.subLocality, pm.thoroughfare].compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: " ")
        }
        var parts: [String] = []
        if let c = city, !c.isEmpty { parts.append(c) }
        if !street.isEmpty, street != city { parts.append(street) }
        return parts.isEmpty ? pm.name : parts.joined(separator: " ")
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
