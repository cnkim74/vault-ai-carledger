import SwiftUI
import StoreKit

/// 프리미엄 페이월 — StoreKit2 자동 갱신 구독 구매 / 복원 / 프로모션 코드.
struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var premium: PremiumStore
    @State private var working = false
    @State private var loading = true
    @State private var restoreMsg: String?

    private let privacyURL = URL(string: "https://cnkim74.github.io/vault-ai-carledger/privacy.html")!
    private let termsURL   = URL(string: "https://cnkim74.github.io/vault-ai-carledger/terms.html")!

    private let perks: [(String, String)] = [
        ("camera.viewfinder", "영수증·충전 화면 촬영 → AI 자동 입력"),
        ("bolt.car.fill", "테슬라·타 브랜드 자동 연동 (API·동글)"),
        ("bolt.fill", "슈퍼차저·충전 이력 자동 가져오기"),
        ("car.2.fill", "차량 여러 대 등록"),
        ("wonsign.circle.fill", "중고 시세 AI 조회"),
        ("chart.line.uptrend.xyaxis", "월간 리포트 · PDF 카톡 공유"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Circle().fill(Theme.goldGradient).frame(width: 64, height: 64)
                        .overlay(Image(systemName: "crown.fill").font(.system(size: 26)).foregroundStyle(Theme.ink))
                        .padding(.top, 12)
                    Text("프리미엄").font(gm(22, .bold))
                    Text("수동 입력은 무료. 자동화는 프리미엄으로.")
                        .font(pd(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)

                    perksCard
                    plansSection
                    footerActions
                    legalFooter
                }
                .padding(20)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .task {
                loading = true
                if premium.products.isEmpty { await premium.loadProducts() }
                loading = false
            }
            .onChange(of: premium.isPremium) { _, isPro in if isPro { dismiss() } }
        }
        .tint(Theme.gold).preferredColorScheme(.dark)
    }

    private var perksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(perks, id: \.0) { perk in
                HStack(spacing: 12) {
                    Image(systemName: perk.0).font(.system(size: 15)).foregroundStyle(Theme.gold).frame(width: 24)
                    Text(perk.1).font(pd(12.5)).foregroundStyle(Theme.text)
                    Spacer()
                }
            }
        }
        .padding(16).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
    }

    @ViewBuilder
    private var plansSection: some View {
        if loading {
            VStack(spacing: 8) {
                ProgressView().tint(Theme.gold)
                Text("구독 상품 불러오는 중…").font(pd(11)).foregroundStyle(Theme.muted)
            }.padding(.vertical, 16)
        } else if premium.products.isEmpty {
            VStack(spacing: 10) {
                Text("지금은 구독 상품을 불러올 수 없어요.")
                    .font(pd(12.5, .semibold)).foregroundStyle(Theme.text)
                Text("네트워크를 확인하고 다시 시도해 주세요. 이미 구매하셨다면 아래 '구매 복원'을 눌러주세요.")
                    .font(pd(11)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                Button {
                    Task { loading = true; await premium.loadProducts(); loading = false }
                } label: {
                    Text("다시 시도").font(pd(13, .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Theme.goldGradient).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(spacing: 10) {
                ForEach(premium.products, id: \.id) { product in
                    Button { Task { await buy(product) } } label: { planRow(product) }
                        .buttonStyle(.plain).disabled(working)
                }
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName).font(pd(14, .semibold)).foregroundStyle(Theme.ink)
                Text(String(format: L("%@ / %@"), product.displayPrice, premium.periodLabel(product)))
                    .font(pd(11)).foregroundStyle(Theme.ink.opacity(0.8))
            }
            Spacer()
            if working { ProgressView().tint(Theme.ink) }
            else { Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.ink.opacity(0.7)) }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.goldGradient).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var footerActions: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                Button { Task { await restore() } } label: {
                    HStack(spacing: 5) {
                        if working { ProgressView().controlSize(.mini).tint(Theme.gold) }
                        Text("구매 복원").font(pd(12, .semibold)).foregroundStyle(Theme.gold)
                    }
                }
                Text("·").foregroundStyle(Theme.muted)
                Button { presentOfferCode() } label: {
                    Text("프로모션 코드").font(pd(12, .semibold)).foregroundStyle(Theme.gold)
                }
            }
            .disabled(working)
            if let restoreMsg { Text(restoreMsg).font(pd(10.5)).foregroundStyle(Theme.muted) }
            #if DEBUG
            Button { premium.debugToggle() } label: {
                Text("개발용: 프리미엄 켜기").font(pd(10.5)).foregroundStyle(Theme.muted2)
            }.padding(.top, 2)
            #endif
        }
    }

    private func restore() async {
        working = true; restoreMsg = nil; defer { working = false }
        let ok = await premium.restore()
        if ok { dismiss() } else { restoreMsg = L("복원할 구매 내역이 없어요.") }
    }

    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text("구독은 자동 갱신되며, 현재 기간 종료 24시간 전에 취소하지 않으면 동일 금액으로 갱신됩니다. 결제는 App Store 계정으로 청구되며, 설정 > Apple 계정에서 관리·해지할 수 있어요.")
                .font(pd(9.5)).foregroundStyle(Theme.muted2).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Link("이용약관", destination: termsURL).font(pd(10)).foregroundStyle(Theme.muted)
                Link("개인정보처리방침", destination: privacyURL).font(pd(10)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 4)
    }

    private func buy(_ product: Product) async {
        working = true; defer { working = false }
        _ = await premium.purchase(product)   // 성공 시 onChange(isPremium)에서 dismiss
    }

    /// 애플 오퍼 코드(프로모션) 입력 시트
    private func presentOfferCode() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        Task {
            try? await AppStore.presentOfferCodeRedeemSheet(in: scene)
            await premium.refresh()
        }
    }
}
