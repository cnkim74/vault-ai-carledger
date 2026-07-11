import SwiftUI
import MapKit

/// 차량 현재 위치를 지도에 표시. 위치 권한(vehicle_location) 없으면 재연결 안내.
struct VehicleLocationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var tesla: TeslaService
    var consumer: ConsumerSession?
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            ZStack {
                if let loc = tesla.location {
                    Map(position: $camera) {
                        Marker(loc.name ?? L("내 차"),
                               systemImage: "car.fill",
                               coordinate: CLLocationCoordinate2D(latitude: loc.lat, longitude: loc.long))
                            .tint(Theme.gold)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) { infoBar(loc) }
                } else {
                    placeholder
                }
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationTitle("차량 위치")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(tesla.locationLoading)
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .task { tesla.consumer = consumer; if tesla.location == nil { await reload() } }
    }

    private func reload() async {
        await tesla.loadLocation()
        if let loc = tesla.location {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: loc.lat, longitude: loc.long),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        }
    }

    private func infoBar(_ loc: TeslaService.VehicleLocation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "car.fill").foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 1) {
                Text(loc.name ?? L("내 차")).font(pd(13, .semibold)).foregroundStyle(Theme.text)
                if let s = statusText(loc.status) {
                    Text(s).font(pd(10.5)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            Button {
                let url = URL(string: "http://maps.apple.com/?daddr=\(loc.lat),\(loc.long)&dirflg=d")
                if let url { UIApplication.shared.open(url) }
            } label: {
                Label("길찾기", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(pd(12, .semibold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.goldGradient).clipShape(Capsule())
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(16)
    }

    private func statusText(_ s: String?) -> String? {
        switch s {
        case "charging": return L("충전 중")
        case "driving": return L("주행 중")
        case "parked": return L("주차 중")
        default: return nil
        }
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            if tesla.locationLoading {
                ProgressView().tint(Theme.gold)
                Text("차량 위치를 불러오는 중…").font(pd(12)).foregroundStyle(Theme.muted)
                Text("차량이 잠자는 중이면 깨우느라 시간이 걸릴 수 있어요.")
                    .font(pd(10.5)).foregroundStyle(Theme.muted2).multilineTextAlignment(.center)
            } else {
                Image(systemName: "mappin.slash").font(.system(size: 32)).foregroundStyle(Theme.muted)
                Text(tesla.locationError ?? L("차량 위치를 불러오지 못했어요"))
                    .font(pd(13)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
                if tesla.locationNeedsReconnect {
                    Button {
                        Task {
                            tesla.consumer = consumer
                            await tesla.connect()
                            if tesla.connected { await reload() }
                        }
                    } label: {
                        Text("테슬라 다시 연결").font(pd(13, .semibold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(Theme.goldGradient).clipShape(Capsule())
                    }
                } else {
                    Button { Task { await reload() } } label: {
                        Text("다시 시도").font(pd(13, .semibold)).foregroundStyle(Theme.gold)
                    }
                }
            }
        }
        .padding(30)
    }
}
