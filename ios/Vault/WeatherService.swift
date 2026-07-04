import Foundation

/// Open-Meteo 현재 날씨 (API 키 불필요·무료).
/// 위치 권한 없이 서울 좌표를 기본값으로 사용한다.
@MainActor
final class WeatherService: ObservableObject {
    @Published var tempC: Int?
    @Published var symbol = "sun.max.fill"
    @Published var label = ""

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let weathercode: Int
        }
        let current_weather: Current
    }

    func load(latitude: Double = 37.5665, longitude: Double = 126.9780) async {
        guard let url = URL(string:
            "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current_weather=true"
        ) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let res = try JSONDecoder().decode(Response.self, from: data)
            tempC = Int(res.current_weather.temperature.rounded())
            (symbol, label) = Self.describe(code: res.current_weather.weathercode)
        } catch {
            print("[WeatherService] load failed: \(error)")
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
}
