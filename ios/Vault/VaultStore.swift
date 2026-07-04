import Foundation

/// Supabase(PostgREST)에서 차량/기록을 읽는 스토어.
/// Secrets가 비어 있거나 요청이 실패하면 목업 데이터로 동작한다.
@MainActor
final class VaultStore: ObservableObject {
    @Published var vehicle: Vehicle = MockData.vehicle
    @Published var records: [VaultRecord] = MockData.records
    @Published var live = false

    func load() async {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else { return }

        do {
            let vehicles: [Vehicle] = try await fetch(
                base: base, key: key,
                path: "rest/v1/vehicles",
                query: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "order", value: "created_at"),
                    URLQueryItem(name: "limit", value: "1"),
                ]
            )
            guard let v = vehicles.first else { return }

            let recs: [VaultRecord] = try await fetch(
                base: base, key: key,
                path: "rest/v1/records",
                query: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "vehicle_id", value: "eq.\(v.id.uuidString.lowercased())"),
                    URLQueryItem(name: "order", value: "occurred_at.desc"),
                    URLQueryItem(name: "limit", value: "10"),
                ]
            )

            vehicle = v
            records = recs
            live = true
        } catch {
            // 폴백: 목업 유지
            print("[VaultStore] Supabase load failed: \(error)")
        }
    }

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
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        var req = URLRequest(url: base.appendingPathComponent("rest/v1/records"))
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")

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
        req.httpBody = try JSONEncoder().encode(body)

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        await load()
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
