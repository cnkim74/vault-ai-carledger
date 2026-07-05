import SwiftUI
import CoreLocation

/// 다가오는 캘린더 일정 → 티맵/카카오맵 길찾기 카드.
struct DestinationCard: View {
    @ObservedObject var calendar: CalendarService
    @State private var pending: Destination?

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d(E) HH:mm"
        return f
    }()

    var body: some View {
        Group {
            if !calendar.destinations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.system(size: 12)).foregroundStyle(Theme.gold)
                        Text("다가오는 일정").font(pd(13, .semibold))
                    }
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
            }
        }
    }
}
