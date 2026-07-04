import Foundation

enum RecordKind: String, Codable {
    case charge, drive, maintenance
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

    enum CodingKeys: String, CodingKey {
        case id, name, plate, battery
        case fuelType = "fuel_type"
        case odometerKm = "odometer_km"
        case leaseLimitKm = "lease_limit_km"
        case leaseDrivenKm = "lease_driven_km"
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
        leaseDrivenKm: 17200
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
