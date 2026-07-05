import Foundation
import EventKit
import CoreLocation

struct Destination: Identifiable {
    let id = UUID()
    let title: String
    let location: String
    let date: Date
    var coordinate: CLLocationCoordinate2D?
}

/// 캘린더에서 다가오는 일정(장소 포함)을 읽어 목적지 목록으로 변환.
/// 좌표는 이벤트의 구조화 위치 또는 주소 지오코딩으로 확보.
@MainActor
final class CalendarService: ObservableObject {
    @Published var destinations: [Destination] = []
    @Published var denied = false

    private let store = EKEventStore()

    func load() async {
        // 테스트용: DEMO_DEST=1 이면 샘플 목적지(강남역)
        if ProcessInfo.processInfo.environment["DEMO_DEST"] == "1" {
            destinations = [
                Destination(title: "강남 미팅", location: "강남역", date: Date().addingTimeInterval(3600),
                            coordinate: CLLocationCoordinate2D(latitude: 37.4979, longitude: 127.0276)),
                Destination(title: "판교 방문", location: "판교역", date: Date().addingTimeInterval(3 * 3600),
                            coordinate: CLLocationCoordinate2D(latitude: 37.3948, longitude: 127.1112)),
            ]
            return
        }

        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            granted = (try? await store.requestAccess(to: .event)) ?? false
        }
        guard granted else { denied = true; return }

        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }
        let pred = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: pred)
            .filter { !($0.location ?? "").isEmpty }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)

        var result: [Destination] = []
        for e in events {
            var d = Destination(title: e.title ?? "일정", location: e.location ?? "",
                                date: e.startDate, coordinate: nil)
            if let geo = e.structuredLocation?.geoLocation {
                d.coordinate = geo.coordinate
            } else if let placemark = try? await CLGeocoder().geocodeAddressString(e.location ?? "").first {
                d.coordinate = placemark.location?.coordinate
            }
            if d.coordinate != nil { result.append(d) }
        }
        destinations = result
    }
}
