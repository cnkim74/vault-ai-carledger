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
