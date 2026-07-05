import SwiftUI

enum MainTab: String {
    case home, records, stats, garage
}

/// 공용 하단 탭바 — 홈 / 기록 / (+) / 통계 / 차고
struct TabBarView: View {
    @Binding var tab: MainTab
    var onAdd: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            item(.home, icon: "house", label: "홈")
            Spacer()
            item(.records, icon: "line.3.horizontal", label: "기록")
            Spacer()
            Button(action: onAdd) {
                Circle()
                    .fill(Theme.goldGradient)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    )
                    .shadow(color: Theme.gold.opacity(0.35), radius: 9, y: 6)
            }
            .offset(y: -14)
            Spacer()
            item(.stats, icon: "chart.bar", label: "통계")
            Spacer()
            item(.garage, icon: "car", label: "차고")
        }
        .padding(.horizontal, 26)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(
            Theme.bgTop.opacity(0.9)
                .overlay(
                    Rectangle().frame(height: 1).foregroundStyle(Color.white.opacity(0.06)),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func item(_ target: MainTab, icon: String, label: String) -> some View {
        Button {
            tab = target
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 21))
                Text(label)
                    .font(pd(11.5))
            }
            .foregroundStyle(tab == target ? Theme.gold : Theme.muted)
            .frame(minWidth: 52)
        }
    }
}
