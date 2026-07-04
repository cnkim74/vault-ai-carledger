import Foundation

enum RecordKind: String, Codable {
    case charge, drive, maintenance
}

enum Ownership: String, Codable, CaseIterable {
    case purchase, lease, rent

    var label: String {
        switch self {
        case .purchase: return "구매"
        case .lease: return "리스"
        case .rent: return "렌트"
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
    var leaseLimitKm: Int?
    var leaseDrivenKm: Int?
    var ownership: Ownership
    var maker: String?
    var model: String?
    var year: Int?
    var purchasePriceWon: Int?
    var monthlyFeeWon: Int?
    var contractStart: String?
    var contractEnd: String?

    enum CodingKeys: String, CodingKey {
        case id, name, plate, battery, ownership, maker, model, year
        case fuelType = "fuel_type"
        case odometerKm = "odometer_km"
        case leaseLimitKm = "lease_limit_km"
        case leaseDrivenKm = "lease_driven_km"
        case purchasePriceWon = "purchase_price_won"
        case monthlyFeeWon = "monthly_fee_won"
        case contractStart = "contract_start"
        case contractEnd = "contract_end"
    }

    /// 디자인 로직과 동일: rangeKm = battery × 5.03
    var rangeKm: Int { Int((Double(battery) * 5.03).rounded()) }

    var leasePct: Int? {
        guard let limit = leaseLimitKm, let driven = leaseDrivenKm, limit > 0 else { return nil }
        return Int((Double(driven) / Double(limit) * 100).rounded())
    }

    var leaseRemainKm: Int {
        (leaseLimitKm ?? 0) - (leaseDrivenKm ?? 0)
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
              let limit = leaseLimitKm, limit > 0,
              let driven = leaseDrivenKm
        else { return nil }

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

/// 약정거리 초과 예측 결과
struct LeaseProjection {
    let projectedTotalKm: Int   // 계약 만료 시 예상 총 주행
    let overageKm: Int          // 약정 대비: +초과 / -여유
    let allowedToDateKm: Int    // 오늘까지 허용되는 페이스 주행
    let drivenKm: Int           // 현재 약정 주행
    let limitKm: Int            // 약정 km
    let dailyPaceKm: Double     // 하루 평균 주행
    let daysRemaining: Int      // 계약 잔여 일수
    let isOverPace: Bool        // 시간 대비 과속 여부
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

    enum CodingKeys: String, CodingKey {
        case id, kind, title, location, tag
        case occurredAt = "occurred_at"
        case amountWon = "amount_won"
        case distanceKm = "distance_km"
        case durationMin = "duration_min"
        case aiLogged = "ai_logged"
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
