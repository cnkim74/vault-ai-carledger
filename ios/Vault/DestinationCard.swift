import SwiftUI
import CoreLocation

/// 길찾기 카드 — 다가오는 캘린더 일정(있으면) + 목적지 직접 검색.
/// 하단에 티맵 / 카카오맵 선택 버튼을 배치.
struct DestinationCard: View {
    @ObservedObject var calendar: CalendarService
    var consumer: ConsumerSession? = nil
    var isEV: Bool = false
    var coordinate: CLLocationCoordinate2D? = nil
    @StateObject private var tesla = TeslaService()
    @State private var showNearby = false
    @State private var showChargers = false
    @State private var pending: Destination?
    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d(E) HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(Theme.gold)
                Text("길찾기").font(pd(13, .semibold))
            }

            // 가까운 슈퍼차저 (테슬라 연결 시)
            if tesla.connected {
                Button { showNearby = true } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10).fill(Theme.red.opacity(0.14))
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "bolt.fill").font(.system(size: 14)).foregroundStyle(Theme.red))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("가까운 슈퍼차저").font(pd(12.5, .medium))
                            Text("차량 위치 기준 주변 충전소").font(pd(10.5)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // 주변 충전소 찾기 (전기차) — 가까운 슈퍼차저 바로 아래
            if isEV {
                Button { showChargers = true } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10).fill(Theme.green.opacity(0.14))
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "bolt.car.fill").font(.system(size: 14)).foregroundStyle(Theme.green))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("주변 충전소 찾기").font(pd(12.5, .medium))
                            Text("지도에서 보기 · 내비 길찾기").font(pd(10.5)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // 다가오는 캘린더 일정 (있을 때만)
            ForEach(calendar.destinations.prefix(3)) { dest in
                Button {
                    pending = dest
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.gold.opacity(0.12))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 14)).foregroundStyle(Theme.gold)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dest.title).font(pd(12.5, .medium)).lineLimit(1)
                            Text("\(dest.location) · \(Self.df.string(from: dest.date))")
                                .font(pd(10.5)).foregroundStyle(Theme.muted).lineLimit(1)
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
                    .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // 목적지 직접 검색
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                TextField("목적지 검색 (예: 강남역, 서울역)", text: $query)
                    .font(pd(12.5))
                    .foregroundStyle(Theme.text)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { NavLauncher.search(query, app: .tmap) }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))

            // 티맵 / 카카오맵 선택 버튼 (하단)
            HStack(spacing: 8) {
                ForEach(NavApp.allCases) { app in
                    Button {
                        searchFocused = false
                        NavLauncher.search(query, app: app)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location.north.fill").font(.system(size: 11))
                            Text(app.label).font(pd(13, .semibold))
                        }
                        .foregroundStyle(query.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.muted : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            query.trimmingCharacters(in: .whitespaces).isEmpty
                                ? AnyShapeStyle(Color.white.opacity(0.06))
                                : AnyShapeStyle(Theme.goldGradient)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .confirmationDialog("어떤 내비로 안내할까요?",
                            isPresented: Binding(get: { pending != nil },
                                                 set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            ForEach(NavApp.allCases) { app in
                Button(app.label) {
                    if let d = pending, let c = d.coordinate {
                        NavLauncher.route(to: c, name: d.location, app: app)
                    }
                    pending = nil
                }
            }
            Button("취소", role: .cancel) { pending = nil }
        }
        .sheet(isPresented: $showNearby) { NearbySuperchargersView(tesla: tesla, consumer: consumer) }
        .sheet(isPresented: $showChargers) { NearbyChargersView(coordinate: coordinate) }
    }
}
