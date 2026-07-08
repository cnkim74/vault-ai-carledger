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

        // 정비 시기 임박/초과
        if let d = MaintenanceSchedule.upcoming(vehicle: store.vehicle, records: store.records)
            .first(where: { $0.remainingKm <= 500 }) {
            let body = d.isOverdue
                ? String(format: L("%@ 정비 시기가 지났어요."), L(d.item))
                : String(format: L("%@ 정비 시기가 다가와요."), L(d.item))
            add(c, id: "maintenance-due", body: body, trigger: soon(15))
        }
    }

    // MARK: Fleet — 기사 정비 알림 (배정 차량 정비 임박/초과, 매일 오전 9시)
    @Published var fleetEnabled = UserDefaults.standard.bool(forKey: "fleet.notif.enabled")

    /// 기사: 정비 알림 켜기/끄기
    func toggleFleet(vehicles: [FleetVehicle], fleetName: String) async {
        let ids = vehicles.map { "fleet-maint-\($0.id.uuidString)" }
        if fleetEnabled {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            fleetEnabled = false
            UserDefaults.standard.set(false, forKey: "fleet.notif.enabled")
        } else {
            guard await requestAuth() else { return }
            fleetEnabled = true
            UserDefaults.standard.set(true, forKey: "fleet.notif.enabled")
            scheduleFleet(vehicles: vehicles, fleetName: fleetName)
        }
    }

    /// 켜져 있으면 최신 차량 상태로 재예약 (대시보드 로드 시 호출)
    func refreshFleetIfEnabled(vehicles: [FleetVehicle], fleetName: String) async {
        guard fleetEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        scheduleFleet(vehicles: vehicles, fleetName: fleetName)
    }

    private func scheduleFleet(vehicles: [FleetVehicle], fleetName: String) {
        let c = UNUserNotificationCenter.current()
        // 현재 차량들의 기존 예약 정리 후 정비 대상만 재예약
        c.removePendingNotificationRequests(withIdentifiers: vehicles.map { "fleet-maint-\($0.id.uuidString)" })
        var morning = DateComponents(); morning.hour = 9; morning.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: morning, repeats: true)
        for v in vehicles {
            guard let r = v.serviceRemaining else { continue }
            let plate = v.plate ?? v.name ?? v.model ?? "-"
            let body: String
            if r < 0 { body = String(format: L("[%@] %@ 정비 시기가 지났어요."), fleetName, plate) }
            else if r <= 2000 { body = String(format: L("[%@] %@ 정비가 임박했어요 (%dkm 남음)."), fleetName, plate, r) }
            else { continue }
            add(c, id: "fleet-maint-\(v.id.uuidString)", body: body, trigger: trigger)
        }
    }

    /// 정비 대상 차량 수 (버튼 노출 판단용)
    static func maintenanceDueCount(_ vehicles: [FleetVehicle]) -> Int {
        vehicles.filter { if let r = $0.serviceRemaining { return r < 0 || r <= 2000 }; return false }.count
    }

    private func soon(_ seconds: TimeInterval) -> UNNotificationTrigger {
        UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
    }

    private func add(_ c: UNUserNotificationCenter, id: String, body: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = "Wheelet"
        content.body = body
        content.sound = .default
        c.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
