import SwiftUI
import StoreKit

/// 계정 · 설정 — 프로필, 지원(리뷰·문의), 정보(개인정보·약관·버전).
struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var profile: ProfileStore
    @ObservedObject var premium: PremiumStore
    @ObservedObject var fleet: FleetStore
    @ObservedObject var auth: AuthService
    @State private var showProfileEdit = false
    @State private var showFleet = false
    @State private var showInquiry = false
    @State private var showInbox = false
    @State private var isAdmin = false
    @State private var legal: LegalDoc?

    private enum LegalDoc: Identifiable {
        case privacy, terms
        var id: Int { self == .privacy ? 0 : 1 }
        var title: String { self == .privacy ? L("개인정보처리방침") : L("이용약관") }
        var text: String { self == .privacy ? LegalText.privacy : LegalText.terms }
    }

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
                    row("1:1 문의", "envelope.fill") { showInquiry = true }
                }

                // 관리자 (문의함) — 관리자 계정 로그인 시에만
                if isAdmin {
                    Section("관리자") {
                        row("문의함", "tray.full.fill") { showInbox = true }
                    }
                }

                // 정보
                Section("정보") {
                    row("개인정보처리방침", "hand.raised.fill") { legal = .privacy }
                    row("이용약관", "doc.text.fill") { legal = .terms }
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
        .sheet(isPresented: $showFleet) { FleetView(premium: premium, fleet: fleet, auth: auth) }
        .sheet(isPresented: $showInquiry) { InquiryView() }
        .sheet(isPresented: $showInbox) { AdminInboxView(auth: auth) }
        .sheet(item: $legal) { doc in LegalTextView(title: doc.title, body_: doc.text) }
        .task { await checkAdmin() }
        .onChange(of: auth.isAuthenticated) { _, _ in Task { await checkAdmin() } }
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
    /// 로그인 이메일이 관리자(admin_emails)인지 확인 → 문의함 노출 여부.
    /// RLS 자기행 조회라, 관리자면 본인 행이 돌아오고 아니면 빈 배열.
    private func checkAdmin() async {
        guard auth.isAuthenticated,
              let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, let token = await auth.validToken() else {
            isAdmin = false; return
        }
        var comps = URLComponents(url: base.appendingPathComponent("rest/v1/admin_emails"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "select", value: "email"), .init(name: "limit", value: "1")]
        var req = URLRequest(url: comps.url!)
        req.setValue(key, forHTTPHeaderField: "apikey"); req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let rows = try? JSONDecoder().decode([[String: String]].self, from: data) {
            isAdmin = !rows.isEmpty
        } else { isAdmin = false }
    }

    private func requestReview() {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}
