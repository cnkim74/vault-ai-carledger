import Foundation

/// 회사(조직) 단위 차량 그룹
struct Fleet: Codable, Identifiable {
    let id: UUID
    var name: String
    var plan: String
    var join_code: String?
    var owner_id: String?
}

/// 조직 멤버(기사)
struct FleetMember: Codable, Identifiable {
    let id: UUID
    let user_id: String
    let email: String?
    let role: String
}

enum FleetRole { case none, manager, driver }

/// Fleet 소속 차량 (기사 정보 포함)
struct FleetVehicle: Codable, Identifiable {
    let id: UUID
    var plate: String?
    var name: String?
    var model: String?
    var year: Int?
    var category: String
    var fuel: String?
    var odometerKm: Int
    var driverName: String?
    var driverPhone: String?
    var memo: String?
    var status: String
    var nextServiceKm: Int?
    var assignedUserId: String?

    var vehicleCategory: VehicleCategory { VehicleCategory(rawValue: category) ?? .car }
    /// 다음 정비까지 남은 거리 (설정된 경우). 음수=초과.
    var serviceRemaining: Int? { nextServiceKm.map { $0 - odometerKm } }

    enum CodingKeys: String, CodingKey {
        case id, plate, name, model, year, category, fuel, memo, status
        case odometerKm = "odometer_km"
        case driverName = "driver_name"
        case driverPhone = "driver_phone"
        case nextServiceKm = "next_service_km"
        case assignedUserId = "assigned_user_id"
    }
}

/// Fleet 차량 기록 (주유·정비 등)
struct FleetRecord: Codable, Identifiable {
    let id: UUID
    let fleet_vehicle_id: UUID
    let kind: String
    let title: String?
    let amount_won: Int?
    let odometer_km: Int?
    let occurred_at: String
    let memo: String?

    var date: Date {
        ISO8601DateFormatter().date(from: occurred_at)
            ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: occurred_at) }()
            ?? Date()
    }
    var recordKind: RecordKind { RecordKind(rawValue: kind) ?? .fuel }
}

/// Fleet 관리 데이터 계층 (기존 소비자 VaultStore와 독립).
@MainActor
final class FleetStore: ObservableObject {
    @Published var fleets: [Fleet] = []
    @Published var selectedFleetID: UUID?
    @Published var vehicles: [FleetVehicle] = []
    @Published var records: [FleetRecord] = []
    @Published var members: [FleetMember] = []
    @Published var role: FleetRole = .none
    @Published var loading = false

    /// 인증 세션 (Fleet은 로그인 사용자 토큰으로 접근)
    weak var auth: AuthService?
    private var apikey: String { Secrets.supabaseKey ?? "" }
    private func bearer() async -> String { await auth?.validToken() ?? apikey }

    var fleet: Fleet? { fleets.first { $0.id == selectedFleetID } ?? fleets.first }

    struct VehicleUpsert: Encodable {
        var fleet_id: String?
        var plate: String?
        var name: String?
        var model: String?
        var year: Int?
        var category: String?
        var fuel: String?
        var odometer_km: Int?
        var driver_name: String?
        var driver_phone: String?
        var memo: String?
        var status: String?
        var next_service_km: Int?
        var assigned_user_id: String?
    }

    // MARK: 로드 (역할 판별)
    func load(uid: String?) async {
        guard let uid else { return }
        // 소유(관리자) 조직 먼저
        let owned: [Fleet]? = try? await fetch(path: "rest/v1/fleets",
            query: [.init(name: "select", value: "*"),
                    .init(name: "owner_id", value: "eq.\(uid)"),
                    .init(name: "order", value: "created_at.desc")])
        if let owned, !owned.isEmpty {
            role = .manager; fleets = owned; selectedFleetID = owned.first?.id
            await loadVehicles(); await loadMembers()
            return
        }
        // 멤버(기사) 조직
        let member: [Fleet]? = try? await fetch(path: "rest/v1/fleets",
            query: [.init(name: "select", value: "*"), .init(name: "order", value: "created_at.desc")])
        if let member, !member.isEmpty {
            role = .driver; fleets = member; selectedFleetID = member.first?.id
            await loadVehicles()
            return
        }
        role = .none; fleets = []; vehicles = []; records = []
    }

    func loadMembers() async {
        guard let fid = selectedFleetID else { members = []; return }
        let rows: [FleetMember]? = try? await fetch(path: "rest/v1/fleet_members",
            query: [.init(name: "select", value: "*"),
                    .init(name: "fleet_id", value: "eq.\(fid.uuidString.lowercased())")])
        members = (rows ?? []).filter { $0.role == "driver" }
    }

    /// 기사: 참여 코드로 조직 참여 (Edge Function)
    func joinByCode(_ code: String) async -> (ok: Bool, error: String?) {
        guard let base = Secrets.supabaseURL, !apikey.isEmpty else { return (false, L("설정 오류")) }
        let b = await bearer()
        var req = URLRequest(url: base.appendingPathComponent("functions/v1/fleet-join"))
        req.httpMethod = "POST"; req.setValue(apikey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(b)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code])
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (false, L("네트워크 오류")) }
        if obj["ok"] as? Bool == true { return (true, nil) }
        return (false, (obj["message"] as? String) ?? L("코드를 찾을 수 없어요"))
    }

    /// 관리자: 차량에 기사 배정 (해제 시 명시적 null 전송)
    private struct AssignBody: Encodable {
        let assigned_user_id: String?
        enum CodingKeys: String, CodingKey { case assigned_user_id }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            if let uid = assigned_user_id { try c.encode(uid, forKey: .assigned_user_id) }
            else { try c.encodeNil(forKey: .assigned_user_id) }
        }
    }
    func assignDriver(vehicleId: UUID, userId: String?) async {
        try? await send(method: "PATCH", path: "rest/v1/fleet_vehicles",
                        query: [.init(name: "id", value: "eq.\(vehicleId.uuidString.lowercased())")],
                        body: AssignBody(assigned_user_id: userId))
        await loadVehicles()
    }

    func loadVehicles() async {
        guard let fid = selectedFleetID else { vehicles = []; return }
        loading = true; defer { loading = false }
        let rows: [FleetVehicle]? = try? await fetch(path: "rest/v1/fleet_vehicles",
            query: [.init(name: "select", value: "*"),
                    .init(name: "fleet_id", value: "eq.\(fid.uuidString.lowercased())"),
                    .init(name: "order", value: "created_at.desc")])
        vehicles = rows ?? []
        await loadRecords()
    }

    func loadRecords() async {
        guard let fid = selectedFleetID else { records = []; return }
        let rows: [FleetRecord]? = try? await fetch(path: "rest/v1/fleet_records",
            query: [.init(name: "select", value: "*"),
                    .init(name: "fleet_id", value: "eq.\(fid.uuidString.lowercased())"),
                    .init(name: "order", value: "occurred_at.desc")])
        records = rows ?? []
    }

    /// Fleet 차량에 기록 추가 (주유·정비 등)
    func addRecord(vehicleId: UUID, kind: RecordKind, title: String, amountWon: Int?, odometerKm: Int?, memo: String?) async {
        struct Ins: Encodable {
            let fleet_id: String; let fleet_vehicle_id: String; let kind: String
            let title: String; let amount_won: Int?; let odometer_km: Int?; let occurred_at: String; let memo: String?
        }
        guard let fid = selectedFleetID else { return }
        let body = Ins(fleet_id: fid.uuidString.lowercased(), fleet_vehicle_id: vehicleId.uuidString.lowercased(),
                       kind: kind.rawValue, title: title, amount_won: amountWon, odometer_km: odometerKm,
                       occurred_at: ISO8601DateFormatter().string(from: Date()), memo: memo)
        try? await send(method: "POST", path: "rest/v1/fleet_records", query: [], body: body)
        // 차량 누적주행은 DB 트리거(sync_vehicle_odometer)가 역할 무관 자동 갱신
        await loadVehicles() // 갱신된 odometer 반영 (loadRecords 포함)
    }

    // MARK: 비용 집계 (이번 달)
    func monthlyCost(vehicleId: UUID) -> Int {
        let cal = Calendar.current
        return records.filter { $0.fleet_vehicle_id == vehicleId && cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }
            .compactMap { $0.amount_won }.reduce(0, +)
    }
    func monthlyTotals() -> (total: Int, fuel: Int, maintenance: Int, other: Int) {
        let cal = Calendar.current
        let month = records.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .month) }
        var fuel = 0, maint = 0, other = 0
        for r in month {
            let a = r.amount_won ?? 0
            switch r.recordKind {
            case .fuel, .charge: fuel += a
            case .maintenance: maint += a
            default: other += a
            }
        }
        return (fuel + maint + other, fuel, maint, other)
    }

    // MARK: Fleet
    func createFleet(name: String) async {
        struct Ins: Encodable { let name: String; let plan: String; let owner_id: String? }
        guard let base = Secrets.supabaseURL, !apikey.isEmpty else { return }
        let b = await bearer()
        var req = URLRequest(url: base.appendingPathComponent("rest/v1/fleets"))
        req.httpMethod = "POST"; headers(&req, bearer: b)
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONEncoder().encode(Ins(name: name, plan: "trial", owner_id: auth?.userID))
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let rows = try? JSONDecoder().decode([Fleet].self, from: data), let f = rows.first {
            fleets.insert(f, at: 0); selectedFleetID = f.id; vehicles = []
        }
    }

    func selectFleet(_ id: UUID) async {
        guard id != selectedFleetID else { return }
        selectedFleetID = id
        await loadVehicles()
    }

    // MARK: 차량 CRUD
    func addVehicle(_ up: VehicleUpsert) async {
        var up = up; up.fleet_id = selectedFleetID?.uuidString.lowercased()
        try? await send(method: "POST", path: "rest/v1/fleet_vehicles", query: [], body: up)
        await loadVehicles()
    }
    func updateVehicle(id: UUID, _ up: VehicleUpsert) async {
        try? await send(method: "PATCH", path: "rest/v1/fleet_vehicles",
                        query: [.init(name: "id", value: "eq.\(id.uuidString.lowercased())")], body: up)
        await loadVehicles()
    }
    func deleteVehicle(id: UUID) async {
        guard let base = Secrets.supabaseURL, !apikey.isEmpty else { return }
        let b = await bearer()
        var comps = URLComponents(url: base.appendingPathComponent("rest/v1/fleet_vehicles"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        var req = URLRequest(url: comps.url!); req.httpMethod = "DELETE"; headers(&req, bearer: b)
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try? await URLSession.shared.data(for: req)
        await loadVehicles()
    }

    /// 대량삽입 행 — 모든 키를 명시(nil→null)해 PostgREST 배열 삽입 요건 충족
    private struct BulkRow: Encodable {
        let fleet_id: String
        let plate: String?, name: String?, model: String?, fuel: String?
        let driver_name: String?, driver_phone: String?, memo: String?
        let year: Int?
        let category: String, status: String
        let odometer_km: Int
        let next_service_km: Int?
        enum CodingKeys: String, CodingKey {
            case fleet_id, plate, name, model, fuel, driver_name, driver_phone, memo, year, category, status, odometer_km, next_service_km
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(fleet_id, forKey: .fleet_id)
            try c.encode(plate, forKey: .plate)
            try c.encode(name, forKey: .name)
            try c.encode(model, forKey: .model)
            try c.encode(fuel, forKey: .fuel)
            try c.encode(driver_name, forKey: .driver_name)
            try c.encode(driver_phone, forKey: .driver_phone)
            try c.encode(memo, forKey: .memo)
            try c.encode(year, forKey: .year)
            try c.encode(category, forKey: .category)
            try c.encode(status, forKey: .status)
            try c.encode(odometer_km, forKey: .odometer_km)
            try c.encode(next_service_km, forKey: .next_service_km)
        }
    }

    /// CSV 대량 등록 — 한 번에 삽입
    func bulkInsert(_ rows: [VehicleUpsert]) async -> Int {
        guard let fid = selectedFleetID else { return 0 }
        let fidStr = fid.uuidString.lowercased()
        let batch = rows.map { r in
            BulkRow(fleet_id: fidStr, plate: r.plate, name: r.name ?? r.plate ?? r.model,
                    model: r.model, fuel: r.fuel, driver_name: r.driver_name, driver_phone: r.driver_phone,
                    memo: r.memo, year: r.year, category: r.category ?? "car",
                    status: r.status ?? "active", odometer_km: r.odometer_km ?? 0,
                    next_service_km: r.next_service_km)
        }
        do {
            try await send(method: "POST", path: "rest/v1/fleet_vehicles", query: [], body: batch)
            await loadVehicles()
            return batch.count
        } catch { return 0 }
    }

    // MARK: 네트워킹 (사용자 토큰 Bearer)
    private func headers(_ req: inout URLRequest, bearer: String) {
        req.setValue(apikey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    private func fetch<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        guard let base = Secrets.supabaseURL, !apikey.isEmpty else { throw URLError(.userAuthenticationRequired) }
        let b = await bearer()
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        var req = URLRequest(url: comps.url!)
        req.setValue(apikey, forHTTPHeaderField: "apikey"); req.setValue("Bearer \(b)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func send<B: Encodable>(method: String, path: String, query: [URLQueryItem], body: B) async throws {
        guard let base = Secrets.supabaseURL, !apikey.isEmpty else { throw URLError(.userAuthenticationRequired) }
        let b = await bearer()
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!); req.httpMethod = method; headers(&req, bearer: b)
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONEncoder().encode(body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }
}

/// CSV 파서 — 컬럼 순서: 차량번호, 모델, 연식, 연료, 차종, 누적주행, 기사, 연락처
enum FleetCSV {
    static func parse(_ text: String) -> [FleetStore.VehicleUpsert] {
        var out: [FleetStore.VehicleUpsert] = []
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
        for (i, raw) in lines.enumerated() {
            let cols = raw.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard !cols.isEmpty, cols.contains(where: { !$0.isEmpty }) else { continue }
            // 헤더 행 스킵
            if i == 0, cols.first.map({ $0.contains("번호") || $0.lowercased().contains("plate") }) == true { continue }
            func at(_ n: Int) -> String? { n < cols.count && !cols[n].isEmpty ? cols[n] : nil }
            let cat = at(4).flatMap { catCode($0) } ?? "car"
            out.append(.init(
                plate: at(0), name: at(1) ?? at(0), model: at(1),
                year: at(2).flatMap { Int($0) }, category: cat, fuel: at(3),
                odometer_km: at(5).flatMap { Int($0.filter(\.isNumber)) } ?? 0,
                driver_name: at(6), driver_phone: at(7), status: "active"))
        }
        return out
    }
    private static func catCode(_ s: String) -> String {
        if s.contains("바이크") || s.lowercased().contains("motor") { return "motorcycle" }
        if s.contains("스쿠터") || s.lowercased().contains("scooter") { return "scooter" }
        return "car"
    }
}
