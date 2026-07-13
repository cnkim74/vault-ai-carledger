import Foundation
import StoreKit

/// 프리미엄(유료 구독) 상태 — StoreKit2 기반.
/// 여러 화면이 각자 인스턴스를 만들어도, currentEntitlements를 조회하므로 동일 구독 상태로 수렴한다.
/// 실제 상품/가격은 App Store Connect의 자동 갱신 구독으로 등록하고,
/// 로컬 테스트는 Xcode StoreKit Configuration(Vault.storekit)로 검증한다.
@MainActor
final class PremiumStore: ObservableObject {
    @Published var isPremium = false
    @Published var products: [Product] = []
    @Published var purchasing = false

    /// App Store Connect / Vault.storekit 의 상품 ID와 반드시 일치해야 함
    static let monthlyID = "com.cnkim74.vault.premium.monthly"
    static let yearlyID  = "com.cnkim74.vault.premium.yearly"
    static var productIDs: [String] { [monthlyID, yearlyID] }

    /// 프리미엄은 실제 구매(또는 복원)로만 활성. (App Store 심사: 구매 없이 켜지면 리젝)
    /// 테스터에겐 프로모션 코드로 제공. 로컬 확인은 아래 DEBUG PREMIUM 환경변수 사용.
    static let betaUnlockAll = false

    private var updatesTask: Task<Void, Never>?

    init() {
        if Self.betaUnlockAll { isPremium = true; return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["PREMIUM"] == "1" { isPremium = true; return }  // 스크린샷 캡처용(조회 생략)
        #endif
        // 결제/갱신/환불 실시간 반영
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await loadProducts(); await refresh() }
    }
    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        let items = (try? await Product.products(for: Self.productIDs)) ?? []
        products = items.sorted { $0.price < $1.price }   // 월간 먼저
    }

    /// 현재 구독 엔티틀먼트로 isPremium 갱신
    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result,
               Self.productIDs.contains(t.productID), t.revocationDate == nil {
                active = true
            }
        }
        isPremium = active
    }

    /// 구독 구매 → 성공 시 isPremium 갱신
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchasing = true; defer { purchasing = false }
        guard let result = try? await product.purchase() else { return false }
        switch result {
        case .success(let verification):
            if case .verified(let t) = verification {
                await t.finish(); await refresh(); return isPremium
            }
            return false
        case .userCancelled, .pending: return false
        @unknown default: return false
        }
    }

    /// 구매 복원 (기기 변경·재설치 시). 반환값 = 복원 후 프리미엄 여부.
    /// AppStore.sync()가 응답 없이 멈추는 경우를 대비해 타임아웃으로 무한 대기를 막는다.
    @discardableResult
    func restore() async -> Bool {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { try? await AppStore.sync() }
            group.addTask { try? await Task.sleep(nanoseconds: 15_000_000_000) } // 15초 타임아웃
            _ = await group.next()   // 둘 중 먼저 끝나는 것까지만 대기
            group.cancelAll()
        }
        await refresh()
        return isPremium
    }

    /// 월/연 등 갱신 주기 라벨
    func periodLabel(_ product: Product) -> String {
        guard let p = product.subscription?.subscriptionPeriod else { return "" }
        switch p.unit {
        case .day: return p.value == 1 ? L("일") : String(format: L("%d일"), p.value)
        case .week: return L("주")
        case .month: return p.value == 1 ? L("월") : String(format: L("%d개월"), p.value)
        case .year: return L("연")
        @unknown default: return ""
        }
    }

    #if DEBUG
    /// 개발용: StoreKit 없이 게이팅 확인
    func debugToggle() { isPremium.toggle() }
    #endif
}
