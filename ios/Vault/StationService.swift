import Foundation
import CoreLocation

struct Station: Identifiable {
    let id: String
    let name: String
    let brand: String
    let price: Int
    let distanceMeters: Double

    var distanceLabel: String {
        distanceMeters >= 1000
            ? String(format: "%.1fkm", distanceMeters / 1000)
            : "\(Int(distanceMeters))m"
    }
}

/// 주변 주유소(오피넷) 조회 — Supabase Edge Function(nearby-stations) 프록시 경유.
/// 전기차는 오피넷 대상이 아니므로 충전소는 지도 링크로 처리(StationsView).
@MainActor
final class StationService: ObservableObject {
    enum State: Equatable {
        case idle, loading, loaded, noKey, failed
    }

    @Published var state: State = .idle
    @Published var stations: [Station] = []
    @Published var averagePrice: Int?    // 전국 평균 (해당 유종)

    func load(fuel: FuelType, coordinate: CLLocationCoordinate2D) async {
        guard let code = fuel.opinetCode else { state = .idle; return }
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else {
            state = .noKey; return
        }
        state = .loading

        let url = base.appendingPathComponent("functions/v1/nearby-stations")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        let payload: [String: Any] = [
            "lat": coordinate.latitude,
            "lon": coordinate.longitude,
            "fuel": code,
            "radius": 5000,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                state = .failed; return
            }

            struct Response: Decodable {
                struct S: Decodable {
                    let id: String; let name: String; let brand: String
                    let price: Int; let distanceMeters: Double
                }
                let stations: [S]?
                let averages: [String: Int]?
                let error: String?
            }
            let res = try JSONDecoder().decode(Response.self, from: data)

            if res.error == "no_key" { state = .noKey; return }

            stations = (res.stations ?? []).map {
                Station(id: $0.id, name: $0.name, brand: $0.brand, price: $0.price, distanceMeters: $0.distanceMeters)
            }
            averagePrice = res.averages?[code]
            state = stations.isEmpty ? .failed : .loaded
        } catch {
            print("[StationService] failed: \(error)")
            state = .failed
        }
    }
}
