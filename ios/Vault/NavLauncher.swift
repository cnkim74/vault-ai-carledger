import UIKit
import CoreLocation

/// 내비 앱 선택지
enum NavApp: String, CaseIterable, Identifiable {
    case tmap, kakao
    var id: String { rawValue }
    var label: String { self == .tmap ? "티맵" : "카카오맵" }
    var appStore: URL {
        self == .tmap
            ? URL(string: "https://apps.apple.com/kr/app/id431589174")!   // T map
            : URL(string: "https://apps.apple.com/kr/app/id304608425")!   // KakaoMap
    }
}

/// 선택한 내비 앱으로 자동 길찾기 실행. 미설치면 앱스토어로 유도.
enum NavLauncher {
    @MainActor
    static func route(to coord: CLLocationCoordinate2D, name: String, app: NavApp) {
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let scheme: String
        switch app {
        case .tmap:
            scheme = "tmap://route?goalname=\(enc)&goalx=\(coord.longitude)&goaly=\(coord.latitude)"
        case .kakao:
            scheme = "kakaomap://route?ep=\(coord.latitude),\(coord.longitude)&by=CAR"
        }
        guard let url = URL(string: scheme) else { return }
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok { UIApplication.shared.open(app.appStore) }   // 미설치 → 앱스토어
        }
    }

    /// 키워드로 목적지 검색 후 해당 내비 앱에서 길찾기. 좌표 없이 장소명만으로 동작.
    @MainActor
    static func search(_ query: String, app: NavApp) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let scheme = app == .tmap
            ? "tmap://search?name=\(enc)"
            : "kakaomap://look?q=\(enc)"
        guard let url = URL(string: scheme) else { return }
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok { UIApplication.shared.open(app.appStore) }
        }
    }
}

/// 지도 앱 선택지 (단골 센터 길찾기용 — 구글맵 포함)
enum MapApp: String, CaseIterable, Identifiable {
    case tmap, kakao, google
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tmap: return "티맵"
        case .kakao: return "카카오맵"
        case .google: return "구글맵"
        }
    }
    var appStore: URL {
        switch self {
        case .tmap: return URL(string: "https://apps.apple.com/kr/app/id431589174")!
        case .kakao: return URL(string: "https://apps.apple.com/kr/app/id304608425")!
        case .google: return URL(string: "https://apps.apple.com/kr/app/id585027354")!
        }
    }
}

/// 주소/장소명 기반 검색·전화
enum PlaceLauncher {
    /// 좌표가 있으면 정확한 좌표로 길찾기, 없으면 주소/이름으로 검색.
    @MainActor
    static func route(name: String, address: String?, lat: Double?, lng: Double?, app: MapApp) {
        guard let lat, let lng else {
            search((address?.isEmpty == false ? address! : name), app: app)
            return
        }
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let scheme: String
        switch app {
        case .tmap:  scheme = "tmap://route?goalname=\(enc)&goalx=\(lng)&goaly=\(lat)"
        case .kakao: scheme = "kakaomap://route?ep=\(lat),\(lng)&by=CAR"
        case .google: scheme = "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lng)"
        }
        guard let url = URL(string: scheme) else { return }
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok, app != .google { UIApplication.shared.open(app.appStore) }
        }
    }

    /// 주소(또는 장소명)로 지도 앱에서 검색. 구글맵은 https로 열려 미설치 시 웹으로 폴백.
    @MainActor
    static func search(_ query: String, app: MapApp) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let scheme: String
        switch app {
        case .tmap: scheme = "tmap://search?name=\(enc)"
        case .kakao: scheme = "kakaomap://look?q=\(enc)"
        case .google: scheme = "https://www.google.com/maps/search/?api=1&query=\(enc)"
        }
        guard let url = URL(string: scheme) else { return }
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok, app != .google { UIApplication.shared.open(app.appStore) }
        }
    }

    /// 전화 걸기
    @MainActor
    static func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        UIApplication.shared.open(url)
    }
}
