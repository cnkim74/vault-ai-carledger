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
    /// 세차지수 0~100 (높을수록 세차 적합)
    @Published var carWashScore: Int?
    /// 세차지수 등급 (매우 좋음/좋음/보통/나쁨/매우 나쁨)
    @Published var carWashGrade: String = ""
    /// 세차지수 근거 (오늘·내일 강수확률)
    @Published var todayRainProb: Int = 0
    @Published var tomorrowRainProb: Int = 0
    @Published var washReason: String = ""
    /// 바이크 라이딩 지수 0~100 (기온·강수·바람 기반)
    @Published var ridingScore: Int?
    @Published var ridingGrade: String = ""
    @Published var ridingAdvice: String?
    @Published var windKmh: Int = 0
    /// 날씨 조회에 사용된 최종 좌표 (주변 주유소 조회에 재사용)
    @Published var coordinate: CLLocationCoordinate2D?

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
        self.coordinate = coordinate

        struct Response: Decodable {
            struct Current: Decodable {
                let temperature: Double
                let weathercode: Int
                let windspeed: Double?
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

            let probs = res.daily?.precipitation_probability_max ?? []
            let today = probs.first.flatMap { $0 } ?? 0
            let tomorrow = probs.count > 1 ? (probs[1] ?? 0) : today
            todayRainProb = today
            tomorrowRainProb = tomorrow
            let maxRainProb = max(today, tomorrow)
            carAdvice = Self.advice(code: code, rainProb: maxRainProb, temp: tempC ?? 20)
            let score = Self.washScore(code: code, todayRain: today, tomorrowRain: tomorrow)
            carWashScore = score
            carWashGrade = Self.washGrade(score)
            washReason = String(format: L("오늘 강수 %d%% · 내일 %d%%"), today, tomorrow)

            // 라이딩 지수 (바이크)
            let wind = Int((res.current_weather.windspeed ?? 0).rounded())
            windKmh = wind
            let rScore = Self.ridingScore(code: code, todayRain: today, temp: tempC ?? 20, windKmh: wind)
            ridingScore = rScore
            ridingGrade = Self.washGrade(rScore)   // 등급 라벨 재사용
            ridingAdvice = Self.ridingAdvice(code: code, rainProb: today, temp: tempC ?? 20, windKmh: wind)
        } catch {
            print("[WeatherService] fetch failed: \(error)")
            didFetch = false
        }
    }

    /// WMO weather code → (SF Symbol, 한국어 설명)
    private static func describe(code: Int) -> (String, String) {
        switch code {
        case 0: return ("sun.max.fill", L("맑음"))
        case 1, 2: return ("cloud.sun.fill", L("대체로 맑음"))
        case 3: return ("cloud.fill", L("흐림"))
        case 45, 48: return ("cloud.fog.fill", L("안개"))
        case 51...57: return ("cloud.drizzle.fill", L("이슬비"))
        case 61...67: return ("cloud.rain.fill", L("비"))
        case 71...77: return ("cloud.snow.fill", L("눈"))
        case 80...82: return ("cloud.heavyrain.fill", L("소나기"))
        case 85, 86: return ("cloud.snow.fill", L("소낙눈"))
        case 95...99: return ("cloud.bolt.rain.fill", L("뇌우"))
        default: return ("cloud.fill", L("흐림"))
        }
    }

    /// 세차지수 0~100 — 오늘 날씨 + 오늘/내일 강수확률 반영.
    /// 오늘 비가 안 와도 세차 유지가 관건이라 오늘 강수를 더 크게, 내일 강수는 절반만 감점.
    static func washScore(code: Int, todayRain: Int, tomorrowRain: Int) -> Int {
        // 지금 강수/강설 중이면 매우 낮음
        switch code {
        case 51...67, 80...82, 95...99: return max(5, 20 - todayRain / 10)  // 비
        case 71...77, 85, 86: return 10                                      // 눈
        case 45, 48: return 45                                              // 안개
        default: break
        }
        // 맑음/흐림: 강수확률로 감점 (오늘 100%, 내일 50% 가중)
        var score = 100 - Int(Double(todayRain) * 1.0) - Int(Double(tomorrowRain) * 0.5)
        if code == 3 { score -= 8 }          // 흐림 소폭 감점
        if code == 1 || code == 2 { score -= 3 }
        return min(100, max(0, score))
    }

    static func washGrade(_ score: Int) -> String {
        switch score {
        case 80...: return L("매우 좋음")
        case 60..<80: return L("좋음")
        case 40..<60: return L("보통")
        case 20..<40: return L("나쁨")
        default: return L("매우 나쁨")
        }
    }

    /// 날씨 → 차량 관리 코멘트
    private static func advice(code: Int, rainProb: Int, temp: Int) -> String? {
        switch code {
        case 71...77, 85, 86:
            return L("눈길 · 제설제 후 하부 세차 추천")
        case 51...67, 80...82, 95...99:
            return L("비 오는 날 · 세차는 미루세요")
        case 45, 48:
            return L("안개 · 안전 운전하세요")
        default:
            if rainProb >= 50 { return L("비 예보 있음 · 세차는 미루세요") }
            if temp >= 33 { return L("폭염 · 냉각수·타이어 공기압 점검") }
            if temp <= -5 { return L("한파 · 배터리 방전 주의") }
            if rainProb < 30 { return L("세차하기 좋은 날이에요") }
            return nil
        }
    }

    /// 바이크 라이딩 지수 0~100 — 강수·기온·바람 반영 (라이더는 비·바람·저온에 민감).
    static func ridingScore(code: Int, todayRain: Int, temp: Int, windKmh: Int) -> Int {
        // 현재 강수/강설/뇌우면 매우 낮음
        switch code {
        case 51...67, 80...82: return max(5, 20 - todayRain / 10)   // 비
        case 71...77, 85, 86: return 8                              // 눈
        case 95...99: return 5                                      // 뇌우
        case 45, 48: return 35                                      // 안개
        default: break
        }
        var score = 100
        score -= Int(Double(todayRain) * 0.8)          // 강수확률 감점
        if windKmh > 20 { score -= (windKmh - 20) * 2 } // 바람 감점(20km/h↑)
        if temp <= 0 { score -= 45 }                    // 결빙 위험
        else if temp <= 5 { score -= 25 }
        else if temp >= 35 { score -= 25 }
        else if temp >= 32 { score -= 12 }
        if code == 3 { score -= 6 }                     // 흐림 소폭
        return min(100, max(0, score))
    }

    /// 날씨 → 라이딩 코멘트
    private static func ridingAdvice(code: Int, rainProb: Int, temp: Int, windKmh: Int) -> String? {
        switch code {
        case 71...77, 85, 86: return L("노면 결빙·미끄러움 · 라이딩 자제")
        case 51...67, 80...82, 95...99: return L("우천 노면 · 라이딩 자제")
        case 45, 48: return L("안개 · 시야 확보 후 서행")
        default:
            if rainProb >= 50 { return L("비 예보 · 우비·방수 준비") }
            if windKmh >= 35 { return L("강풍 주의 · 차선 유지 유의") }
            if temp <= 3 { return L("저온 · 노면 결빙 주의") }
            if temp >= 33 { return L("폭염 · 수분 보충·휴식") }
            if rainProb < 30 && windKmh < 25 { return L("라이딩하기 좋은 날이에요") }
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
