import SwiftUI
import MapKit
import CoreLocation

/// 주변 전기차 충전소 — 지도 + 목록, 탭하면 티맵·카카오맵·구글맵·애플지도 길찾기 선택.
/// 데이터는 MapKit 장소 검색(MKLocalSearch)으로, 테슬라 연결 없이 모든 사용자에게 동작.
struct NearbyChargersView: View {
    @Environment(\.dismiss) private var dismiss
    var coordinate: CLLocationCoordinate2D?

    struct ChargerPlace: Identifiable {
        let id = UUID()
        let name: String
        let address: String?
        let coordinate: CLLocationCoordinate2D
        let distanceKm: Double?
    }

    @State private var places: [ChargerPlace] = []
    @State private var loading = false
    @State private var error: String?
    @State private var camera: MapCameraPosition = .automatic
    @State private var routeTarget: ChargerPlace?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if loading {
                        loadingView
                    } else if let err = error {
                        message(err)
                    } else if places.isEmpty {
                        message(L("주변 충전소를 찾지 못했어요"))
                    } else {
                        map
                        ForEach(places) { row($0) }
                        Text("현재 위치 기준 검색 결과 · 실시간 이용 현황은 지도 앱에서 확인하세요.")
                            .font(pd(10)).foregroundStyle(Theme.muted).padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("주변 충전소")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await search() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(loading)
                }
            }
            .confirmationDialog("어떤 지도로 안내할까요?",
                                isPresented: Binding(get: { routeTarget != nil }, set: { if !$0 { routeTarget = nil } }),
                                titleVisibility: .visible) {
                ForEach(MapApp.allCases) { app in Button(app.label) { route(app) } }
                Button("애플 지도") { routeApple() }
                Button("취소", role: .cancel) { routeTarget = nil }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .task { if places.isEmpty { await search() } }
    }

    private var map: some View {
        Map(position: $camera) {
            ForEach(places) { p in
                Marker(p.name, systemImage: "bolt.fill", coordinate: p.coordinate).tint(Theme.green)
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            if let c = coordinate ?? places.first?.coordinate {
                camera = .region(MKCoordinateRegion(center: c,
                    span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)))
            }
        }
    }

    private func row(_ p: ChargerPlace) -> some View {
        Button { routeTarget = p } label: {
            HStack(spacing: 12) {
                Circle().fill(Theme.green.opacity(0.16)).frame(width: 36, height: 36)
                    .overlay(Image(systemName: "bolt.fill").font(.system(size: 15)).foregroundStyle(Theme.green))
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name).font(pd(14, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    HStack(spacing: 8) {
                        if let d = p.distanceKm {
                            Label(String(format: "%.1fkm", d), systemImage: "location.fill")
                                .font(pd(11)).foregroundStyle(Theme.silver)
                        }
                        if let a = p.address {
                            Text(a).font(pd(10.5)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                }
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "location.north.fill").font(.system(size: 10))
                    Text("길찾기").font(pd(11, .semibold))
                }
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .overlay(Capsule().stroke(Theme.gold.opacity(0.4), lineWidth: 1))
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12))
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Theme.gold)
            Text("주변 충전소를 찾는 중…").font(pd(12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash").font(.system(size: 30)).foregroundStyle(Theme.muted)
            Text(text).font(pd(13)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Button { Task { await search() } } label: {
                Text("다시 시도").font(pd(13, .semibold)).foregroundStyle(Theme.gold)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44)
    }

    // MARK: 검색
    private func search() async {
        loading = true; error = nil; defer { loading = false }
        let center = coordinate ?? CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780) // 좌표 없으면 서울
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = "전기차 충전소"
        req.region = MKCoordinateRegion(center: center, latitudinalMeters: 8000, longitudinalMeters: 8000)
        if #available(iOS 18.0, *) { req.regionPriority = .required }

        guard let resp = try? await MKLocalSearch(request: req).start() else {
            error = L("주변 충전소를 찾지 못했어요"); return
        }
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let list = resp.mapItems.compactMap { item -> ChargerPlace? in
            let c = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(c) else { return nil }
            let dist = here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) / 1000
            return ChargerPlace(
                name: item.name ?? L("충전소"),
                address: item.placemark.title,
                coordinate: c,
                distanceKm: (dist * 10).rounded() / 10
            )
        }
        .sorted { ($0.distanceKm ?? 999) < ($1.distanceKm ?? 999) }
        places = list
        if let c = list.first?.coordinate ?? coordinate {
            camera = .region(MKCoordinateRegion(center: c,
                span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)))
        }
    }

    private func route(_ app: MapApp) {
        guard let p = routeTarget else { return }
        PlaceLauncher.route(name: p.name, address: p.address, lat: p.coordinate.latitude, lng: p.coordinate.longitude, app: app)
        routeTarget = nil
    }
    private func routeApple() {
        guard let p = routeTarget else { return }
        let s = "http://maps.apple.com/?daddr=\(p.coordinate.latitude),\(p.coordinate.longitude)&dirflg=d"
        if let url = URL(string: s) { UIApplication.shared.open(url) }
        routeTarget = nil
    }
}
