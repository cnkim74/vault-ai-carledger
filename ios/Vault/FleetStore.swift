import Foundation

/// 회사(조직) 단위 차량 그룹
struct Fleet: Codable, Identifiable {
    let id: UUID
    var name: String
    var plan: String
}

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

    var vehicleCategory: VehicleCategory { VehicleCategory(rawValue: category) ?? .car }

    enum CodingKeys: String, CodingKey {
        case id, plate, name, model, year, category, fuel, memo, status
        case odometerKm = "odometer_km"
        case driverName = "driver_name"
        case driverPhone = "driver_phone"
    }
}

/// Fleet 관리 데이터 계층 (기존 소비자 VaultStore와 독립).
@MainActor
final class FleetStore: ObservableObject {
    @Published var fleets: [Fleet] = []
    @Published var selectedFleetID: UUID?
    @Published var vehicles: [FleetVehicle] = []
    @Published var loading = false

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
    }

    // MARK: 로드
    func loadFleets() async {
        guard let rows: [Fleet] = try? await fetch(path: "rest/v1/fleets",
            query: [.init(name: "select", value: "*"), .init(name: "order", value: "created_at.desc")]) else { return }
        fleets = rows
        if selectedFleetID == nil { selectedFleetID = rows.first?.id }
        if selectedFleetID != nil { await loadVehicles() }
    }

    func loadVehicles() async {
        guard let fid = selectedFleetID else { vehicles = []; return }
        loading = true; defer { loading = false }
        let rows: [FleetVehicle]? = try? await fetch(path: "rest/v1/fleet_vehicles",
            query: [.init(name: "select", value: "*"),
                    .init(name: "fleet_id", value: "eq.\(fid.uuidString.lowercased())"),
                    .init(name: "order", value: "created_at.desc")])
        vehicles = rows ?? []
    }

    // MARK: Fleet
    func createFleet(name: String) async {
        struct Ins: Encodable { let name: String; let plan: String }
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return }
        var req = URLRequest(url: base.appendingPathComponent("rest/v1/fleets"))
        req.httpMethod = "POST"; headers(&req, key)
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONEncoder().encode(Ins(name: name, plan: "trial"))
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
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return }
        var comps = URLComponents(url: base.appendingPathComponent("rest/v1/fleet_vehicles"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        var req = URLRequest(url: comps.url!); req.httpMethod = "DELETE"; headers(&req, key)
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
        enum CodingKeys: String, CodingKey {
            case fleet_id, plate, name, model, fuel, driver_name, driver_phone, memo, year, category, status, odometer_km
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
                    status: r.status ?? "active", odometer_km: r.odometer_km ?? 0)
        }
        do {
            try await send(method: "POST", path: "rest/v1/fleet_vehicles", query: [], body: batch)
            await loadVehicles()
            return batch.count
        } catch { return 0 }
    }

    // MARK: 네트워킹
    private func headers(_ req: inout URLRequest, _ key: String) {
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    private func fetch<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { throw URLError(.userAuthenticationRequired) }
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        var req = URLRequest(url: comps.url!)
        req.setValue(key, forHTTPHeaderField: "apikey"); req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func send<B: Encodable>(method: String, path: String, query: [URLQueryItem], body: B) async throws {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { throw URLError(.userAuthenticationRequired) }
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!); req.httpMethod = method; headers(&req, key)
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
