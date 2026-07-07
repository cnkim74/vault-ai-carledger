import Foundation

enum RecordKind: String, Codable {
    case charge, fuel, drive, maintenance

    var label: String {
        switch self {
        case .charge: return L("충전")
        case .fuel: return L("주유")
        case .drive: return L("주행")
        case .maintenance: return L("정비")
        }
    }
}

/// 차종 (자동차 / 바이크 / 스쿠터) — 정비 항목·아이콘·지수 전환의 기반
enum VehicleCategory: String, CaseIterable {
    case car, motorcycle, scooter
    var label: String {
        switch self {
        case .car: return L("자동차")
        case .motorcycle: return L("바이크")
        case .scooter: return L("스쿠터")
        }
    }
    var icon: String {
        switch self {
        case .car: return "car.fill"
        case .motorcycle: return "motorcycle"
        case .scooter: return "scooter"
        }
    }
    var isBike: Bool { self != .car }
}

/// 차종·연료별 예상 정비 항목 (기록 추가 시 빠른 선택)
enum MaintenancePresets {
    static func items(category: VehicleCategory, ev: Bool) -> [String] {
        switch category {
        case .motorcycle:
            return ["엔진오일", "오일필터", "체인 청소", "체인 급유", "체인 조정", "체인 교체",
                    "스프라켓", "앞 타이어", "뒤 타이어", "브레이크 패드", "브레이크 오일",
                    "에어필터", "스파크플러그", "밸브 간극", "배터리", "냉각수"]
        case .scooter:
            return ["엔진오일", "기어오일", "구동벨트", "구동롤러", "앞 타이어", "뒤 타이어",
                    "브레이크 패드", "에어필터", "스파크플러그", "배터리", "냉각수"]
        case .car:
            return ev
                ? ["타이어 위치교환", "타이어 교체", "브레이크 패드", "냉각수 점검",
                   "에어컨 필터", "와이퍼", "하부 세차", "실내필터", "타이어 공기압", "정기 점검"]
                : ["엔진오일", "오일필터", "에어클리너", "점화플러그", "미션오일",
                   "브레이크 패드", "타이어 교체", "부동액", "연료필터", "와이퍼", "배터리", "정기 점검"]
        }
    }
}

enum Ownership: String, Codable, CaseIterable {
    case purchase, lease, rent

    var label: String {
        switch self {
        case .purchase: return L("구매")
        case .lease: return L("리스")
        case .rent: return L("렌트")
        }
    }
}

/// 연료 종류 (차계부 표준)
enum FuelType: String, CaseIterable {
    case ev = "전기차"
    case gasoline = "가솔린"
    case diesel = "디젤"
    case hybrid = "하이브리드"
    case lpg = "LPG"
    case hydrogen = "수소"

    /// 표시용 지역화 라벨 (rawValue는 DB 저장값이라 유지)
    var label: String { L(rawValue) }

    /// 오피넷 유종 코드 (전기/수소는 없음)
    var opinetCode: String? {
        switch self {
        case .gasoline, .hybrid: return "B027"
        case .diesel: return "D047"
        case .lpg: return "K015"
        case .ev, .hydrogen: return nil
        }
    }
}

struct Vehicle: Codable, Identifiable {
    let id: UUID
    var name: String
    var plate: String?
    var fuelType: String
    var battery: Int
    var odometerKm: Int
    var odometerStartKm: Int?   // 계약 시작 시 주행거리 (신차면 0)
    var leaseLimitKm: Int?
    var leaseDrivenKm: Int?     // (레거시) 수동 저장값 — 이제 odometer 기반 파생값을 사용
    var ownership: Ownership
    var maker: String?
    var model: String?
    var year: Int?
    var purchasePriceWon: Int?
    var monthlyFeeWon: Int?
    var contractStart: String?
    var contractEnd: String?
    var category: String?       // 차종: car / motorcycle / scooter (기본 car)

    enum CodingKeys: String, CodingKey {
        case id, name, plate, battery, ownership, maker, model, year, category
        case fuelType = "fuel_type"
        case odometerKm = "odometer_km"
        case odometerStartKm = "odometer_start_km"
        case leaseLimitKm = "lease_limit_km"
        case leaseDrivenKm = "lease_driven_km"
        case purchasePriceWon = "purchase_price_won"
        case monthlyFeeWon = "monthly_fee_won"
        case contractStart = "contract_start"
        case contractEnd = "contract_end"
    }

    /// 차종 (기본 car)
    var vehicleCategory: VehicleCategory { VehicleCategory(rawValue: category ?? "car") ?? .car }
    var isBike: Bool { vehicleCategory.isBike }

    /// 디자인 로직과 동일: rangeKm = battery × 5.03
    var rangeKm: Int { Int((Double(battery) * 5.03).rounded()) }

    /// 계약 이후 실제 주행거리 = 누적주행 − 계약 시작 시 주행거리 (음수 방지).
    /// odometer/시작값이 유효하지 않으면 레거시 lease_driven_km로 폴백.
    var leaseDriven: Int {
        let start = odometerStartKm ?? 0
        if odometerKm >= start && (odometerStartKm != nil || odometerKm > 0) {
            return max(0, odometerKm - start)
        }
        return leaseDrivenKm ?? 0
    }

    var leasePct: Int? {
        guard let limit = leaseLimitKm, limit > 0 else { return nil }
        return Int((Double(leaseDriven) / Double(limit) * 100).rounded())
    }

    var leaseRemainKm: Int {
        (leaseLimitKm ?? 0) - leaseDriven
    }

    /// 연료가 주유 대상(전기·수소 제외)인지
    var usesFuel: Bool {
        fuelType != FuelType.ev.rawValue && fuelType != FuelType.hydrogen.rawValue
    }

    /// 계약서 기반 약정거리 초과 예측.
    /// 계약일·약정일·약정km·현재 약정주행이 모두 있어야 계산됨.
    func leaseProjection(asOf: Date = Date()) -> LeaseProjection? {
        guard let startStr = contractStart, let start = Self.parseDay(startStr),
              let endStr = contractEnd, let end = Self.parseDay(endStr),
              let limit = leaseLimitKm, limit > 0
        else { return nil }
        let driven = leaseDriven

        let cal = Calendar(identifier: .gregorian)
        let totalDays = max(1, cal.dateComponents([.day], from: start, to: end).day ?? 1)
        let rawElapsed = cal.dateComponents([.day], from: start, to: asOf).day ?? 0
        let elapsed = min(max(1, rawElapsed), totalDays)
        let remaining = max(0, totalDays - elapsed)

        let dailyPace = Double(driven) / Double(elapsed)
        let projectedTotal = Int((dailyPace * Double(totalDays)).rounded())
        let overage = projectedTotal - limit

        let timeProgress = Double(elapsed) / Double(totalDays)
        let distProgress = Double(driven) / Double(limit)

        return LeaseProjection(
            projectedTotalKm: projectedTotal,
            overageKm: overage,
            allowedToDateKm: Int((Double(limit) * timeProgress).rounded()),
            drivenKm: driven,
            limitKm: limit,
            dailyPaceKm: dailyPace,
            elapsedDays: elapsed,
            totalDays: totalDays,
            daysRemaining: remaining,
            isOverPace: distProgress > timeProgress
        )
    }

    static func parseDay(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
}

/// 월 지출 집계 (이번 달 / 지난달 비교 + 항목별)
struct MonthlySpend {
    let month: Int          // 이번 달 (1~12)
    let total: Int          // 이번 달 총 지출
    let prevTotal: Int      // 지난달 총 지출
    let charge: Int         // 충전
    let fuel: Int           // 주유
    let maintenance: Int    // 정비
    let other: Int          // 기타

    var deltaWon: Int { total - prevTotal }
    var deltaPct: Int? {
        guard prevTotal > 0 else { return nil }
        return Int((Double(total - prevTotal) / Double(prevTotal) * 100).rounded())
    }

    /// 0원이 아닌 항목만 (라벨, 금액, 색상키)
    var breakdown: [(label: String, amount: Int, key: String)] {
        [("충전", charge, "charge"), ("주유", fuel, "fuel"),
         ("정비", maintenance, "maintenance"), ("기타", other, "other")]
            .filter { $0.1 > 0 }
    }
}

/// 약정거리 초과 예측 결과
struct LeaseProjection {
    let projectedTotalKm: Int   // 계약 만료 시 예상 총 주행
    let overageKm: Int          // 약정 대비: +초과 / -여유
    let allowedToDateKm: Int    // 오늘까지 허용되는 페이스 주행
    let drivenKm: Int           // 현재 약정 주행
    let limitKm: Int            // 약정 km
    let dailyPaceKm: Double     // 하루 평균 주행
    let elapsedDays: Int        // 계약 경과 일수
    let totalDays: Int          // 총 계약 일수
    let daysRemaining: Int      // 계약 잔여 일수
    let isOverPace: Bool        // 시간 대비 과속 여부

    /// 오늘까지 적정 주행 대비 현재 주행 비율(%). 100 = 딱 적정, >100 = 초과 페이스.
    var paceRatioPct: Int {
        guard allowedToDateKm > 0 else { return 0 }
        return Int((Double(drivenKm) / Double(allowedToDateKm) * 100).rounded())
    }

    /// 약정 기준 적정 하루 주행 (약정 ÷ 총 계약일)
    var allowedDailyKm: Int {
        guard totalDays > 0 else { return 0 }
        return Int((Double(limitKm) / Double(totalDays)).rounded())
    }
}

struct VaultRecord: Codable, Identifiable {
    let id: UUID
    var kind: RecordKind
    var title: String
    var occurredAt: Date
    var amountWon: Int?
    var distanceKm: Double?
    var durationMin: Int?
    var location: String?
    var tag: String?
    var aiLogged: Bool
    var odometerKm: Int?    // 기록 시점 누적 주행거리 (정비 주기 계산용)

    enum CodingKeys: String, CodingKey {
        case id, kind, title, location, tag
        case occurredAt = "occurred_at"
        case amountWon = "amount_won"
        case distanceKm = "distance_km"
        case durationMin = "duration_min"
        case aiLogged = "ai_logged"
        case odometerKm = "odometer_km"
    }
}

/// 정비 예정 항목 (다음 정비까지 남은 거리)
struct MaintenanceDue: Identifiable {
    let id = UUID()
    let item: String
    let intervalKm: Int
    let lastKm: Int
    let dueKm: Int
    var remainingKm: Int   // 음수면 초과(지남)
    var isOverdue: Bool { remainingKm < 0 }
}

/// 정비 체크리스트 항목 (기록 없는 항목 포함)
struct MaintenanceCheck: Identifiable {
    let id = UUID()
    let item: String
    let intervalKm: Int
    let lastKm: Int?        // nil = 정비 기록 없음
    let remainingKm: Int?   // nil = 기록 없음
    var isOverdue: Bool { (remainingKm ?? .max) < 0 }
    var isSoon: Bool { if let r = remainingKm { return r >= 0 && r <= 1000 }; return false }
}

/// 차종별 정비 주기(km) + 기록 기반 다음 정비 계산
enum MaintenanceSchedule {
    /// (항목, 주기 km) — 차종·연료별 기본값
    static func intervals(category: VehicleCategory, ev: Bool) -> [(String, Int)] {
        switch category {
        case .motorcycle:
            return [("엔진오일", 5000), ("오일필터", 10000), ("체인 급유", 800), ("체인 조정", 2000),
                    ("앞 타이어", 12000), ("뒤 타이어", 8000), ("브레이크 패드", 15000),
                    ("스파크플러그", 12000), ("에어필터", 12000)]
        case .scooter:
            return [("엔진오일", 4000), ("기어오일", 8000), ("구동벨트", 20000),
                    ("앞 타이어", 10000), ("뒤 타이어", 10000), ("브레이크 패드", 15000), ("에어필터", 12000)]
        case .car:
            return ev
                ? [("타이어 위치교환", 10000), ("타이어 교체", 50000), ("브레이크 패드", 40000), ("에어컨 필터", 15000)]
                : [("엔진오일", 10000), ("오일필터", 10000), ("에어클리너", 20000),
                   ("타이어 위치교환", 10000), ("브레이크 패드", 30000), ("점화플러그", 40000)]
        }
    }

    /// 전체 점검 체크리스트 — 기록 없는 항목도 포함(상태 표시용). 임박/초과 우선 정렬.
    static func checklist(vehicle: Vehicle, records: [VaultRecord]) -> [MaintenanceCheck] {
        let odo = vehicle.odometerKm
        var out: [MaintenanceCheck] = []
        for (item, interval) in intervals(category: vehicle.vehicleCategory, ev: !vehicle.usesFuel) {
            let last = records
                .filter { $0.kind == .maintenance && $0.odometerKm != nil && $0.title.contains(item) }
                .max(by: { $0.occurredAt < $1.occurredAt })
            if let lastKm = last?.odometerKm {
                out.append(.init(item: item, intervalKm: interval, lastKm: lastKm, remainingKm: lastKm + interval - odo))
            } else {
                out.append(.init(item: item, intervalKm: interval, lastKm: nil, remainingKm: nil))
            }
        }
        // 정렬: 초과 → 임박 → 기록있음(남은거리 오름) → 기록없음
        return out.sorted { a, b in
            switch (a.remainingKm, b.remainingKm) {
            case let (ra?, rb?): return ra < rb
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false
            }
        }
    }

    /// 정비 기록의 주행거리를 기준으로 다음 정비까지 남은 거리 계산 (가까운 순)
    static func upcoming(vehicle: Vehicle, records: [VaultRecord]) -> [MaintenanceDue] {
        let odo = vehicle.odometerKm
        var out: [MaintenanceDue] = []
        for (item, interval) in intervals(category: vehicle.vehicleCategory, ev: !vehicle.usesFuel) {
            let last = records
                .filter { $0.kind == .maintenance && $0.odometerKm != nil && $0.title.contains(item) }
                .max(by: { $0.occurredAt < $1.occurredAt })
            guard let lastKm = last?.odometerKm else { continue }
            let due = lastKm + interval
            out.append(.init(item: item, intervalKm: interval, lastKm: lastKm, dueKm: due, remainingKm: due - odo))
        }
        return out.sorted { $0.remainingKm < $1.remainingKm }
    }
}

/// 차량 실시간 상태 (테슬라 shift_state·charging 기반)
enum VehicleLiveStatus: String {
    case driving, parked, charging
    var label: String {
        switch self {
        case .driving: return L("운행 중")
        case .parked: return L("주차 중")
        case .charging: return L("충전 중")
        }
    }
    var icon: String {
        switch self {
        case .driving: return "steeringwheel"
        case .parked: return "parkingsign"
        case .charging: return "bolt.fill"
        }
    }
}

/// 단골 센터 분류
enum PlaceCategory: String, CaseIterable {
    case garage, repair, service, wash, charge, other
    var label: String {
        switch self {
        case .garage: return L("정비소")
        case .repair: return L("카센터")
        case .service: return L("서비스센터")
        case .wash: return L("세차장")
        case .charge: return L("충전소")
        case .other: return L("기타")
        }
    }
    var icon: String {
        switch self {
        case .garage, .repair: return "wrench.and.screwdriver.fill"
        case .service: return "building.2.fill"
        case .wash: return "drop.fill"
        case .charge: return "bolt.fill"
        case .other: return "mappin.circle.fill"
        }
    }
}

/// 단골 정비소·카센터·서비스센터 등
struct ServicePlace: Codable, Identifiable {
    let id: UUID
    var name: String
    var category: String
    var address: String?
    var phone: String?
    var memo: String?
    var latitude: Double?
    var longitude: Double?

    var placeCategory: PlaceCategory { PlaceCategory(rawValue: category) ?? .garage }
    var hasCoordinate: Bool { latitude != nil && longitude != nil }

    enum CodingKeys: String, CodingKey {
        case id, name, category, address, phone, memo, latitude, longitude
    }
}

// ── 표시 헬퍼 ─────────────────────────────────────────

func relativeDay(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "오늘" }
    if cal.isDateInYesterday(date) { return "어제" }
    let c = cal.dateComponents([.month, .day], from: date)
    return "\(c.month ?? 0)/\(c.day ?? 0)"
}

func timeOf(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}

func won(_ amount: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "ko_KR")
    return "₩" + (f.string(from: NSNumber(value: amount)) ?? "\(amount)")
}

func grouped(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "ko_KR")
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

// ── 목업 (디자인 원본과 동일 · 네트워크 실패 시 폴백) ──

enum MockData {
    static let vehicle = Vehicle(
        id: UUID(),
        name: "Model Y Long Range",
        plate: "62가 3817",
        fuelType: "전기차",
        battery: 82,
        odometerKm: 24318,
        odometerStartKm: 0,
        leaseLimitKm: 20000,
        leaseDrivenKm: 17200,
        ownership: .rent,
        maker: "테슬라",
        model: "Model Y Long Range",
        year: 2024,
        purchasePriceWon: nil,
        monthlyFeeWon: 890000,
        contractStart: "2024-07-01",
        contractEnd: "2027-06-30"
    )

    static var records: [VaultRecord] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ dayOffset: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            cal.date(byAdding: DateComponents(day: dayOffset, hour: hour, minute: minute), to: today) ?? today
        }
        return [
            VaultRecord(id: UUID(), kind: .charge, title: "초급속 충전 · 42kWh", occurredAt: at(0, 7, 12),
                        amountWon: 14900, distanceKm: nil, durationMin: nil,
                        location: "이마트 성수", tag: nil, aiLogged: true),
            VaultRecord(id: UUID(), kind: .drive, title: "주행 일지 · 서울 → 판교", occurredAt: at(-1, 8, 40),
                        amountWon: nil, distanceKm: 38.2, durationMin: 21,
                        location: nil, tag: "출퇴근", aiLogged: false),
            VaultRecord(id: UUID(), kind: .maintenance, title: "엔진오일 교체 알림", occurredAt: at(-2),
                        amountWon: nil, distanceKm: nil, durationMin: nil,
                        location: "세컨카", tag: "2,000km 남음", aiLogged: false),
        ]
    }
}
