import Foundation
import CoreLocation

/// 위치 기반 현재 날씨 + 차량 관리 코멘트.
/// - 위치: CoreLocation(사용 중 권한). 거부/실패 시 서울 좌표 폴백.
/// - 날씨: Open-Meteo (API 키 불필요·무료). 현재 날씨 + 2일 강수확률로 세차 조언 생성.
@MainActor
final class WeatherService: NSObject, ObservableObject {
    @Published var tempC: Int?
    @Published var symbol = "sun.max.fill"
    @Published var label = ""
    @Published var city = "서울"
    /// 차량 관리 코멘트 (예: "세차하기 좋은 날이에요")
    @Published var carAdvice: String?

    private let manager = CLLocationManager()
    private let fallback = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
    private var didFetch = false

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // 권한 응답이 없거나 느리면 5초 후 서울로 폴백
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !didFetch { await fetch(coordinate: fallback) }
            }
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            Task { await fetch(coordinate: fallback) }
        }
    }

    private func fetch(coordinate: CLLocationCoordinate2D) async {
        guard !didFetch else { return }
        didFetch = true

        struct Response: Decodable {
            struct Current: Decodable {
                let temperature: Double
                let weathercode: Int
            }
            struct Daily: Decodable {
                let precipitation_probability_max: [Int?]
            }
            let current_weather: Current
            let daily: Daily?
        }

        guard let url = URL(string:
            "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)"
            + "&current_weather=true&daily=precipitation_probability_max&forecast_days=2&timezone=auto"
        ) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let res = try JSONDecoder().decode(Response.self, from: data)
            let code = res.current_weather.weathercode
            tempC = Int(res.current_weather.temperature.rounded())
            (symbol, label) = Self.describe(code: code)

            let maxRainProb = (res.daily?.precipitation_probability_max ?? [])
                .compactMap { $0 }.max() ?? 0
            carAdvice = Self.advice(code: code, rainProb: maxRainProb, temp: tempC ?? 20)
        } catch {
            print("[WeatherService] fetch failed: \(error)")
            didFetch = false
        }
    }

    /// WMO weather code → (SF Symbol, 한국어 설명)
    private static func describe(code: Int) -> (String, String) {
        switch code {
        case 0: return ("sun.max.fill", "맑음")
        case 1, 2: return ("cloud.sun.fill", "대체로 맑음")
        case 3: return ("cloud.fill", "흐림")
        case 45, 48: return ("cloud.fog.fill", "안개")
        case 51...57: return ("cloud.drizzle.fill", "이슬비")
        case 61...67: return ("cloud.rain.fill", "비")
        case 71...77: return ("cloud.snow.fill", "눈")
        case 80...82: return ("cloud.heavyrain.fill", "소나기")
        case 85, 86: return ("cloud.snow.fill", "소낙눈")
        case 95...99: return ("cloud.bolt.rain.fill", "뇌우")
        default: return ("cloud.fill", "흐림")
        }
    }

    /// 날씨 → 차량 관리 코멘트
    private static func advice(code: Int, rainProb: Int, temp: Int) -> String? {
        switch code {
        case 71...77, 85, 86:
            return "눈길 · 제설제 후 하부 세차 추천"
        case 51...67, 80...82, 95...99:
            return "비 오는 날 · 세차는 미루세요"
        case 45, 48:
            return "안개 · 안전 운전하세요"
        default:
            if rainProb >= 50 { return "비 예보 있음 · 세차는 미루세요" }
            if temp >= 33 { return "폭염 · 냉각수·타이어 공기압 점검" }
            if temp <= -5 { return "한파 · 배터리 방전 주의" }
            if rainProb < 30 { return "세차하기 좋은 날이에요" }
            return nil
        }
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                await self.fetch(coordinate: self.fallback)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            // 도시명 역지오코딩 (실패해도 좌표 날씨는 진행)
            if let placemark = try? await CLGeocoder().reverseGeocodeLocation(loc).first {
                self.city = placemark.subLocality ?? placemark.locality ?? "현재 위치"
            }
            await self.fetch(coordinate: loc.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            await self.fetch(coordinate: self.fallback)
        }
    }
}
