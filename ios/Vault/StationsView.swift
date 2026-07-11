import SwiftUI
import CoreLocation

/// 홈 화면용 주변 주유소·충전소 카드.
/// - 주유 차량: 오피넷 최저가 주유소 + 전국 평균, 탭 → 전체 목록 시트
/// - 전기차/수소: 카카오맵 충전소 검색 링크
struct StationsCard: View {
    @ObservedObject var store: VaultStore
    @ObservedObject var weather: WeatherService
    @StateObject private var service = StationService()
    @State private var showSheet = false
    @State private var showChargers = false
    @Environment(\.openURL) private var openURL

    private var fuel: FuelType {
        FuelType(rawValue: store.vehicle.fuelType) ?? .gasoline
    }

    var body: some View {
        Group {
            if store.vehicle.usesFuel {
                fuelCard
            } else {
                evCard
            }
        }
        .padding(.horizontal, 16)
        .task(id: cardTaskID) {
            if store.vehicle.usesFuel, let coord = weather.coordinate {
                await service.load(fuel: fuel, coordinate: coord)
            }
        }
        .sheet(isPresented: $showSheet) {
            StationsSheet(service: service, fuel: fuel)
        }
        .sheet(isPresented: $showChargers) {
            NearbyChargersView(coordinate: weather.coordinate)
        }
    }

    // 위치·차량이 준비되면 조회 (좌표 확정 시점에 트리거)
    private var cardTaskID: String {
        "\(store.vehicle.id)-\(weather.coordinate?.latitude ?? 0)"
    }

    // 주유소 카드
    @ViewBuilder
    private var fuelCard: some View {
        Button {
            if service.state == .loaded { showSheet = true }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.orange.opacity(0.14))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "fuelpump.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.orange)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("주변 주유소")
                        .font(pd(12.5, .semibold))
                    stationSubtitle
                }
                Spacer()
                trailing
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var stationSubtitle: some View {
        switch service.state {
        case .loaded:
            if let cheapest = service.stations.min(by: { $0.price < $1.price }) {
                Text(verbatim: String(format: L("최저 %@ · %@"), cheapest.brand, cheapest.distanceLabel))
                    .font(pd(10.5))
                    .foregroundStyle(Theme.muted)
            }
        case .loading:
            Text("주변 검색 중…").font(pd(10.5)).foregroundStyle(Theme.muted)
        case .noKey:
            Text("오피넷 키 설정 필요").font(pd(10.5)).foregroundStyle(Theme.muted)
        case .failed:
            Text("주변 정보를 불러오지 못했어요").font(pd(10.5)).foregroundStyle(Theme.muted)
        case .idle:
            Text("위치 확인 중…").font(pd(10.5)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch service.state {
        case .loaded:
            HStack(spacing: 8) {
                if let cheapest = service.stations.min(by: { $0.price < $1.price }) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(won(cheapest.price)).font(gm(14, .bold)).foregroundStyle(Theme.gold)
                        if let avg = service.averagePrice {
                            Text(verbatim: String(format: L("평균 %@"), won(avg))).font(pd(9.5)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        case .loading:
            ProgressView().controlSize(.small).tint(Theme.gold)
        default:
            EmptyView()
        }
    }

    // 전기차 충전소 카드 — 카카오맵 실시간 충전소 검색 링크
    private var evCard: some View {
        Button {
            showChargers = true
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.green.opacity(0.14))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "bolt.car.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.green)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("주변 충전소 찾기")
                        .font(pd(12.5, .semibold))
                    Text(verbatim: String(format: L("%@ 주변 · 지도에서 보기"), weather.city))
                        .font(pd(10.5))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// 주변 주유소 전체 목록 시트 (가격순)
struct StationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var service: StationService
    let fuel: FuelType

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    if let avg = service.averagePrice {
                        HStack {
                            Text(verbatim: String(format: L("전국 평균 (%@)"), L(fuel.rawValue))).font(pd(12)).foregroundStyle(Theme.muted)
                            Spacer()
                            Text(won(avg)).font(gm(13, .medium)).foregroundStyle(Theme.silver)
                        }
                        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    ForEach(Array(service.stations.sorted { $0.price < $1.price }.enumerated()), id: \.element.id) { idx, s in
                        Button {
                            let q = s.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "https://map.kakao.com/?q=\(q)") { openURL(url) }
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(idx + 1)")
                                    .font(gm(12, .bold))
                                    .foregroundStyle(idx == 0 ? Theme.gold : Theme.muted)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name).font(pd(12.5, .medium)).lineLimit(1)
                                    Text("\(s.brand) · \(s.distanceLabel)")
                                        .font(pd(10.5)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text(won(s.price))
                                    .font(gm(14, .medium))
                                    .foregroundStyle(idx == 0 ? Theme.gold : Theme.text)
                                Image(systemName: "map").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationTitle("주변 주유소")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
    }
}
