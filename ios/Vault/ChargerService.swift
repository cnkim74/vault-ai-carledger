import Foundation
import CoreLocation

struct Charger: Identifiable {
    let id: String
    let name: String
    let addr: String
    let distanceMeters: Double
    let available: Int
    let total: Int
    let fast: Bool

    var distanceLabel: String {
        distanceMeters >= 1000
            ? String(format: "%.1fkm", distanceMeters / 1000)
            : "\(Int(distanceMeters))m"
    }
}

/// 주변 전기차 충전소 실시간 조회 — Supabase Edge Function(nearby-chargers) → KECO 프록시.
@MainActor
final class ChargerService: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, noKey, failed }

    @Published var state: State = .idle
    @Published var chargers: [Charger] = []

    func load(coordinate: CLLocationCoordinate2D) async {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else {
            state = .noKey; return
        }
        state = .loading

        var req = URLRequest(url: base.appendingPathComponent("functions/v1/nearby-chargers"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 25
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "lat": coordinate.latitude, "lon": coordinate.longitude, "radius": 5000,
        ])

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                state = .failed; return
            }
            struct Response: Decodable {
                struct C: Decodable {
                    let id: String; let name: String; let addr: String
                    let distanceMeters: Double; let available: Int; let total: Int; let fast: Bool
                }
                let chargers: [C]?
                let error: String?
            }
            let res = try JSONDecoder().decode(Response.self, from: data)
            if res.error == "no_key" { state = .noKey; return }
            chargers = (res.chargers ?? []).map {
                Charger(id: $0.id, name: $0.name, addr: $0.addr, distanceMeters: $0.distanceMeters,
                        available: $0.available, total: $0.total, fast: $0.fast)
            }
            state = chargers.isEmpty ? .failed : .loaded
        } catch {
            print("[ChargerService] failed: \(error)")
            state = .failed
        }
    }
}
