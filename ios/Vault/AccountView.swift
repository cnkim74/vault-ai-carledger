import SwiftUI
import StoreKit

/// 계정 · 설정 — 프로필, 지원(리뷰·문의), 정보(개인정보·약관·버전).
struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var profile: ProfileStore
    @ObservedObject var premium: PremiumStore
    @State private var showProfileEdit = false
    @State private var showFleet = false

    // TODO: 실제 배포 시 도메인/이메일로 교체
    private let privacyURL = URL(string: "https://cnkim74.github.io/wheelet/privacy.html")!
    private let termsURL = URL(string: "https://cnkim74.github.io/wheelet/terms.html")!
    private let supportEmail = "cnkim74@gmail.com"

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                // 프로필
                Section {
                    Button { showProfileEdit = true } label: {
                        HStack(spacing: 14) {
                            Circle().fill(Theme.goldGradient).frame(width: 46, height: 46)
                                .overlay(Text(profile.initials).font(gm(16, .bold)).foregroundStyle(Theme.ink))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.greetingName).font(pd(15, .semibold)).foregroundStyle(Theme.text)
                                Text(premium.isPremium ? "프리미엄 이용 중" : "무료 이용 중")
                                    .font(pd(11)).foregroundStyle(premium.isPremium ? Theme.gold : Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                }

                // 기업용
                Section("기업용") {
                    Button { showFleet = true } label: {
                        HStack {
                            Label { Text("기업용 Fleet").foregroundStyle(Theme.text) } icon: { Image(systemName: "building.2.fill").foregroundStyle(Theme.gold) }
                            Spacer()
                            Text("택시·운송·렌터카").font(pd(10.5)).foregroundStyle(Theme.muted)
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                    }
                }

                // 지원
                Section("지원") {
                    row("앱 평가하기", "star.fill") { requestReview() }
                    row("1:1 문의", "envelope.fill") { openMail() }
                }

                // 정보
                Section("정보") {
                    linkRow("개인정보처리방침", "hand.raised.fill", privacyURL)
                    linkRow("이용약관", "doc.text.fill", termsURL)
                    HStack {
                        Label { Text("버전") } icon: { Image(systemName: "info.circle.fill").foregroundStyle(Theme.gold) }
                        Spacer()
                        Text(appVersion).font(pd(12)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .navigationTitle("계정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showProfileEdit) { ProfileSheet(profile: profile) }
        .sheet(isPresented: $showFleet) { FleetView(premium: premium) }
    }

    private func row(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label { Text(title).foregroundStyle(Theme.text) } icon: { Image(systemName: icon).foregroundStyle(Theme.gold) }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }
    private func linkRow(_ title: String, _ icon: String, _ url: URL) -> some View {
        row(title, icon) { UIApplication.shared.open(url) }
    }

    private func requestReview() {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
    private func openMail() {
        let subject = "Wheelet 문의".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(supportEmail)?subject=\(subject)") { UIApplication.shared.open(url) }
    }
}
