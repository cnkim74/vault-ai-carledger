import SwiftUI

/// 프리미엄 안내 시트 — 스캔 자동입력 등 유료 기능 소개.
/// 실제 결제(StoreKit) 연동 전까지는 '체험 시작'으로 기능을 열 수 있다.
struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var premium: PremiumStore

    private let perks: [(String, String)] = [
        ("camera.viewfinder", "영수증·충전 화면 촬영 → AI 자동 입력"),
        ("bolt.car.fill", "테슬라 등 차량 자동 연동"),
        ("chart.line.uptrend.xyaxis", "월간 AI 리포트 · 무제한 인사이트"),
        ("bell.badge", "스마트 알림 · 무제한 기록 보관"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Circle()
                    .fill(Theme.goldGradient)
                    .frame(width: 68, height: 68)
                    .overlay(Image(systemName: "crown.fill").font(.system(size: 28)).foregroundStyle(Theme.ink))
                    .padding(.top, 16)

                Text("프리미엄").font(gm(22, .bold))
                Text("촬영 한 번으로 기록을 자동으로 채워요.")
                    .font(pd(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(perks, id: \.0) { perk in
                        HStack(spacing: 12) {
                            Image(systemName: perk.0).font(.system(size: 16)).foregroundStyle(Theme.gold).frame(width: 26)
                            Text(perk.1).font(pd(13)).foregroundStyle(Theme.text)
                            Spacer()
                        }
                    }
                }
                .padding(16)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))

                Spacer()

                Button {
                    premium.activateTrial()
                    dismiss()
                } label: {
                    Text("체험 시작")
                        .font(pd(15, .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.goldGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Text("결제 연동(App Store 구독)은 추후 제공됩니다.")
                    .font(pd(10)).foregroundStyle(Theme.muted)
            }
            .padding(20)
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
    }
}
