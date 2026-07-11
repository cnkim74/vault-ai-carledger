import SwiftUI
import MapKit

/// 차량 기준 주변 슈퍼차저 안내 — 지도 + 목록, 탭하면 티맵·카카오맵·애플지도 길찾기 선택.
struct NearbySuperchargersView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tesla: TeslaService
    var consumer: ConsumerSession?
    @State private var camera: MapCameraPosition = .automatic
    @State private var routeTarget: TeslaService.NearbyCharger?

    private var pinned: [TeslaService.NearbyCharger] {
        tesla.nearby.filter { $0.lat != nil && $0.long != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if tesla.nearbyLoading {
                        loading
                    } else if let err = tesla.nearbyError {
                        message(err)
                    } else if tesla.nearby.isEmpty {
                        message(L("주변 슈퍼차저가 없어요"))
                    } else {
                        if !pinned.isEmpty { map }
                        ForEach(tesla.nearby) { row($0) }
                        Text("차량 현재 위치 기준 · 거리·이용 현황은 실시간이 아닐 수 있어요.")
                            .font(pd(10)).foregroundStyle(Theme.muted).padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("가까운 슈퍼차저")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { tesla.consumer = consumer; await tesla.loadNearby() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.disabled(tesla.nearbyLoading)
                }
            }
            .confirmationDialog("어떤 지도로 안내할까요?",
                                isPresented: Binding(get: { routeTarget != nil },
                                                     set: { if !$0 { routeTarget = nil } }),
                                titleVisibility: .visible) {
                ForEach(MapApp.allCases) { app in
                    Button(app.label) { route(app) }
                }
                Button("애플 지도") { routeApple() }
                Button("취소", role: .cancel) { routeTarget = nil }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .task { tesla.consumer = consumer; if tesla.nearby.isEmpty { await tesla.loadNearby() } }
    }

    private var map: some View {
        Map(position: $camera) {
            ForEach(pinned) { c in
                Marker(c.name, systemImage: "bolt.fill",
                       coordinate: CLLocationCoordinate2D(latitude: c.lat!, longitude: c.long!))
                    .tint(c.closed ? Theme.muted : Theme.red)
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            if let c = pinned.first {
                camera = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: c.lat!, longitude: c.long!),
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
            }
        }
    }

    private func row(_ c: TeslaService.NearbyCharger) -> some View {
        Button { routeTarget = c } label: {
            HStack(spacing: 12) {
                Circle().fill(Theme.red.opacity(0.16)).frame(width: 36, height: 36)
                    .overlay(Image(systemName: "bolt.fill").font(.system(size: 15)).foregroundStyle(Theme.red))
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.name).font(pd(14, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    HStack(spacing: 8) {
                        if let d = c.distanceKm {
                            Label(String(format: "%.1fkm", d), systemImage: "location.fill")
                                .font(pd(11)).foregroundStyle(Theme.silver)
                        }
                        if c.closed {
                            Text("운영 중지").font(pd(10.5, .semibold)).foregroundStyle(Theme.muted)
                        } else if let a = c.availableStalls, let t = c.totalStalls {
                            Text(verbatim: "\(a)/\(t) 이용 가능")
                                .font(pd(11, .medium)).foregroundStyle(a > 0 ? Theme.green : Theme.orange)
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

    private func route(_ app: MapApp) {
        guard let c = routeTarget else { return }
        PlaceLauncher.route(name: c.name, address: nil, lat: c.lat, lng: c.long, app: app)
        routeTarget = nil
    }
    private func routeApple() {
        guard let c = routeTarget else { return }
        let q = c.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Supercharger"
        let s = (c.lat != nil && c.long != nil)
            ? "http://maps.apple.com/?daddr=\(c.lat!),\(c.long!)&dirflg=d"
            : "http://maps.apple.com/?q=\(q)"
        if let url = URL(string: s) { UIApplication.shared.open(url) }
        routeTarget = nil
    }

    private var loading: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Theme.gold)
            Text("주변 슈퍼차저를 찾는 중…").font(pd(12)).foregroundStyle(Theme.muted)
            Text("차량이 잠자는 중이면 깨우느라 시간이 걸릴 수 있어요.")
                .font(pd(10.5)).foregroundStyle(Theme.muted2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.slash").font(.system(size: 30)).foregroundStyle(Theme.muted)
            Text(text).font(pd(13)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Button { Task { tesla.consumer = consumer; await tesla.loadNearby() } } label: {
                Text("다시 시도").font(pd(13, .semibold)).foregroundStyle(Theme.gold)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44)
    }
}
