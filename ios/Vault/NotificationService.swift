import Foundation
import UserNotifications

/// 로컬 알림 — 매일 아침 브리핑 + 상황별 스마트 알림(약정 초과 페이스·배터리 부족·세차 적기).
@MainActor
final class NotificationService: ObservableObject {
    @Published var enabled = UserDefaults.standard.bool(forKey: "notif.enabled")

    /// 벨 탭 → 켜기(권한 요청 후 예약) / 끄기(예약 취소)
    func toggle(store: VaultStore, weather: WeatherService) async {
        if enabled {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            enabled = false
            UserDefaults.standard.set(false, forKey: "notif.enabled")
        } else {
            guard await requestAuth() else { return }   // 거부 시 켜지 않음
            enabled = true
            UserDefaults.standard.set(true, forKey: "notif.enabled")
            await schedule(store: store, weather: weather)
        }
    }

    /// 이미 켜져 있으면 최신 데이터로 알림 재예약 (홈 로드 시 호출)
    func refreshIfEnabled(store: VaultStore, weather: WeatherService) async {
        guard enabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        await schedule(store: store, weather: weather)
    }

    private func requestAuth() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    private func schedule(store: VaultStore, weather: WeatherService) async {
        let c = UNUserNotificationCenter.current()
        c.removeAllPendingNotificationRequests()

        // 매일 아침 8시 브리핑 (반복)
        var morning = DateComponents(); morning.hour = 8; morning.minute = 0
        add(c, id: "daily-briefing",
            body: L("오늘의 차량 브리핑을 확인해 보세요."),
            trigger: UNCalendarNotificationTrigger(dateMatching: morning, repeats: true))

        // 약정거리 초과 페이스 경고
        if let p = store.vehicle.leaseProjection(), p.isOverPace {
            add(c, id: "lease-pace",
                body: L("약정거리 초과 페이스예요. 주행 속도를 조절해 보세요."),
                trigger: soon(6))
        }

        // 전기차 배터리 부족
        if store.vehicle.fuelType == FuelType.ev.rawValue && store.vehicle.battery < 15 {
            add(c, id: "battery-low",
                body: L("배터리가 부족해요. 충전이 필요해요."),
                trigger: soon(9))
        }

        // 세차 적기
        if let score = weather.carWashScore, score >= 60 {
            add(c, id: "wash-good",
                body: L("오늘은 세차하기 좋은 날이에요."),
                trigger: soon(12))
        }
    }

    private func soon(_ seconds: TimeInterval) -> UNNotificationTrigger {
        UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
    }

    private func add(_ c: UNUserNotificationCenter, id: String, body: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = "VAULT"
        content.body = body
        content.sound = .default
        c.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
