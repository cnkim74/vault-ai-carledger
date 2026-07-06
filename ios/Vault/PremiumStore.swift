import Foundation

/// 프리미엄(유료 구독) 상태.
/// 지금은 로컬 플래그로 게이팅만 구현 — 실제 결제는 StoreKit 구독 연동 시 이 값을
/// App Store 영수증 검증 결과로 교체한다. (서버 과금 API는 Edge Function에서 재검증 권장)
@MainActor
final class PremiumStore: ObservableObject {
    @Published var isPremium: Bool = UserDefaults.standard.bool(forKey: "premium.active")

    /// 체험 활성화 (테스트/온보딩용). 실제 배포 시 결제 성공 콜백으로 대체.
    func activateTrial() {
        isPremium = true
        UserDefaults.standard.set(true, forKey: "premium.active")
    }

    func deactivate() {
        isPremium = false
        UserDefaults.standard.set(false, forKey: "premium.active")
    }
}
