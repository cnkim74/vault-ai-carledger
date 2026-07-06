import Foundation

/// Supabase(PostgREST)에서 차량/기록을 읽고 쓰는 스토어.
/// Secrets가 비어 있거나 요청이 실패하면 목업 데이터로 동작한다.
/// 다중 차량: vehicles 배열 + 선택된 차량(selectedVehicleID, UserDefaults 영속화).
@MainActor
final class VaultStore: ObservableObject {
    @Published var vehicles: [Vehicle] = [MockData.vehicle]
    @Published var records: [VaultRecord] = MockData.records
    @Published var live = false
    @Published var selectedVehicleID: UUID?
    @Published var monthlySpend: MonthlySpend?
    /// 테슬라 동기화 시 갱신되는 실시간 상태 (운행/주차/충전)
    @Published var liveStatus: VehicleLiveStatus?

    private static let selectedKey = "vault.selectedVehicleID"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.selectedKey) {
            selectedVehicleID = UUID(uuidString: raw)
        }
    }

    /// 현재 선택된 차량 (없으면 첫 번째)
    var vehicle: Vehicle {
        vehicles.first(where: { $0.id == selectedVehicleID }) ?? vehicles.first ?? MockData.vehicle
    }

    func load() async {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return }

        do {
            let fetched: [Vehicle] = try await fetch(
                base: base, key: key,
                path: "rest/v1/vehicles",
                query: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "order", value: "created_at"),
                ]
            )
            guard !fetched.isEmpty else { return }

            vehicles = fetched
            if selectedVehicleID == nil || !fetched.contains(where: { $0.id == selectedVehicleID }) {
                selectedVehicleID = fetched.first?.id
            }
            try await loadRecords()
            live = true
        } catch {
            print("[VaultStore] Supabase load failed: \(error)")
        }
    }

    /// 차량 전환 — 선택을 영속화하고 해당 차량의 기록을 다시 불러온다.
    func select(_ id: UUID) {
        guard id != selectedVehicleID else { return }
        selectedVehicleID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.selectedKey)
        Task { try? await loadRecords() }
    }

    private func loadRecords() async throws {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey else { return }
        let recs: [VaultRecord] = try await fetch(
            base: base, key: key,
            path: "rest/v1/records",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "vehicle_id", value: "eq.\(vehicle.id.uuidString.lowercased())"),
                URLQueryItem(name: "order", value: "occurred_at.desc"),
                URLQueryItem(name: "limit", value: "10"),
            ]
        )
        records = recs
        try await loadSpend()
    }

    /// 이번 달·지난달 지출을 실제 기록에서 집계.
    private func loadSpend() async throws {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey else { return }

        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let startThis = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let startPrev = cal.date(byAdding: .month, value: -1, to: startThis) ?? startThis
        let iso = ISO8601DateFormatter()

        let recs: [VaultRecord] = try await fetch(
            base: base, key: key,
            path: "rest/v1/records",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "vehicle_id", value: "eq.\(vehicle.id.uuidString.lowercased())"),
                URLQueryItem(name: "occurred_at", value: "gte.\(iso.string(from: startPrev))"),
                URLQueryItem(name: "order", value: "occurred_at.desc"),
                URLQueryItem(name: "limit", value: "500"),
            ]
        )

        var total = 0, prev = 0, charge = 0, fuel = 0, maint = 0, other = 0
        for r in recs {
            guard let amount = r.amountWon, amount > 0 else { continue }
            let inThisMonth = r.occurredAt >= startThis
            if inThisMonth {
                total += amount
                switch r.kind {
                case .charge: charge += amount
                case .fuel: fuel += amount
                case .maintenance: maint += amount
                case .drive: other += amount
                }
            } else {
                prev += amount
            }
        }

        monthlySpend = MonthlySpend(
            month: cal.component(.month, from: now),
            total: total, prevTotal: prev,
            charge: charge, fuel: fuel, maintenance: maint, other: other
        )
    }

    // ── 기록 추가 ─────────────────────────────────────

    struct RecordInsert: Encodable {
        let vehicle_id: String
        let kind: String
        let title: String
        let occurred_at: String
        let amount_won: Int?
        let distance_km: Double?
        let duration_min: Int?
        let location: String?
        let tag: String?
        let ai_logged: Bool
    }

    /// 새 기록을 Supabase에 저장하고 목록을 새로고침한다.
    func addRecord(
        kind: RecordKind, title: String,
        amountWon: Int? = nil, distanceKm: Double? = nil, durationMin: Int? = nil,
        location: String? = nil, tag: String? = nil
    ) async throws {
        let iso = ISO8601DateFormatter()
        let body = RecordInsert(
            vehicle_id: vehicle.id.uuidString.lowercased(),
            kind: kind.rawValue,
            title: title,
            occurred_at: iso.string(from: Date()),
            amount_won: amountWon,
            distance_km: distanceKm,
            duration_min: durationMin,
            location: location,
            tag: tag,
            ai_logged: false
        )
        try await send(method: "POST", path: "rest/v1/records", query: [], body: body)
        await load()
    }

    /// 기존 기록 수정 (모든 필드 덮어쓰기 · nil은 명시적으로 null 저장)
    func updateRecord(
        id: UUID, kind: RecordKind, title: String,
        amountWon: Int? = nil, distanceKm: Double? = nil, durationMin: Int? = nil,
        location: String? = nil, tag: String? = nil
    ) async throws {
        struct RecordPatch: Encodable {
            let kind: String, title: String
            let amount_won: Int?, duration_min: Int?
            let distance_km: Double?
            let location: String?, tag: String?
            enum CodingKeys: String, CodingKey {
                case kind, title, amount_won, distance_km, duration_min, location, tag
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(kind, forKey: .kind)
                try c.encode(title, forKey: .title)
                try c.encode(amount_won, forKey: .amount_won)      // nil → null (값 지우기 반영)
                try c.encode(distance_km, forKey: .distance_km)
                try c.encode(duration_min, forKey: .duration_min)
                try c.encode(location, forKey: .location)
                try c.encode(tag, forKey: .tag)
            }
        }
        let body = RecordPatch(kind: kind.rawValue, title: title, amount_won: amountWon,
                               duration_min: durationMin, distance_km: distanceKm,
                               location: location, tag: tag)
        try await send(method: "PATCH", path: "rest/v1/records",
                       query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
                       body: body)
        await load()
    }

    /// 기록 삭제
    func deleteRecord(id: UUID) async throws {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        var comps = URLComponents(url: base.appendingPathComponent("rest/v1/records"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        applyHeaders(&req, key: key)
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        await load()
    }

    // ── 차량 추가/수정 ─────────────────────────────────

    struct VehicleUpsert: Encodable {
        var name: String?
        var plate: String?
        var fuel_type: String?
        var battery: Int?
        var odometer_km: Int?
        var odometer_start_km: Int?
        var lease_limit_km: Int?
        var ownership: String?
        var maker: String?
        var model: String?
        var year: Int?
        var purchase_price_won: Int?
        var monthly_fee_won: Int?
        var contract_start: String?
        var contract_end: String?
    }

    /// 새 차량을 등록하고 그 차량을 선택한다.
    func addVehicle(_ insert: VehicleUpsert) async throws {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        var req = URLRequest(url: base.appendingPathComponent("rest/v1/vehicles"))
        req.httpMethod = "POST"
        applyHeaders(&req, key: key)
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONEncoder().encode(insert)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // 반환된 행에서 새 차량 id를 얻어 선택
        struct Row: Decodable { let id: UUID }
        if let rows = try? JSONDecoder().decode([Row].self, from: data), let new = rows.first {
            await load()
            select(new.id)
        } else {
            await load()
        }
    }

    /// 현재 선택된 차량 정보를 수정하고 새로고침한다. (nil 필드는 변경하지 않음)
    func updateVehicle(_ update: VehicleUpsert) async throws {
        try await send(
            method: "PATCH",
            path: "rest/v1/vehicles",
            query: [URLQueryItem(name: "id", value: "eq.\(vehicle.id.uuidString.lowercased())")],
            body: update
        )
        await load()
    }

    // ── 공통 헬퍼 ─────────────────────────────────────

    private func applyHeaders(_ req: inout URLRequest, key: String) {
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func send<B: Encodable>(method: String, path: String, query: [URLQueryItem], body: B) async throws {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        applyHeaders(&req, key: key)
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONEncoder().encode(body)

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func fetch<T: Decodable>(base: URL, key: String, path: String, query: [URLQueryItem]) async throws -> T {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        var req = URLRequest(url: comps.url!)
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            if let date = Self.parseTimestamp(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Unparsable date: \(s)"))
        }
        return try decoder.decode(T.self, from: data)
    }

    /// PostgREST timestamptz: 소수점 자릿수가 0~6자리로 다양해서 유연하게 파싱
    private static func parseTimestamp(_ s: String) -> Date? {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        // 마이크로초(6자리) 등 — 소수부 제거 후 재시도
        if let dotIdx = s.firstIndex(of: ".") {
            let head = String(s[..<dotIdx])
            let tail = s[dotIdx...].drop(while: { $0 == "." || $0.isNumber })
            return iso.date(from: head + tail)
        }
        return nil
    }
}
