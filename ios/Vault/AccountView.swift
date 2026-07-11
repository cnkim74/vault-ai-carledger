import SwiftUI
import StoreKit

/// 계정 · 설정 — 프로필, 지원(리뷰·문의), 정보(개인정보·약관·버전).
struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var profile: ProfileStore
    @ObservedObject var premium: PremiumStore
    @ObservedObject var fleet: FleetStore
    @ObservedObject var auth: AuthService
    @ObservedObject var adminStore: AdminStore
    @State private var showProfileEdit = false
    @State private var showFleet = false
    @State private var showInquiry = false
    @State private var showShortcuts = false
    @State private var showInbox = false
    @State private var showDeleteConfirm = false
    @State private var deleting = false
    @State private var deleteError: String?
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
                    row("카드문자 자동입력 설정", "creditcard.fill") { showShortcuts = true }
                    row("앱 평가하기", "star.fill") { requestReview() }
                    row("1:1 문의", "envelope.fill") { showInquiry = true }
                }

                // 관리자 (문의함) — 관리자 계정 로그인 시에만
                if adminStore.isAdmin {
                    Section("관리자") {
                        Button { showInbox = true } label: {
                            HStack {
                                Label { Text("문의함").foregroundStyle(Theme.text) } icon: { Image(systemName: "tray.full.fill").foregroundStyle(Theme.gold) }
                                Spacer()
                                if adminStore.pendingCount > 0 {
                                    Text("\(adminStore.pendingCount)").font(pd(11, .bold)).foregroundStyle(.white)
                                        .frame(minWidth: 18).padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Theme.red).clipShape(Capsule())
                                }
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }

                // 로그인 계정 (Supabase Auth) — 로그아웃 / 계정 삭제
                if auth.isAuthenticated {
                    Section("로그인 계정") {
                        HStack {
                            Label { Text("이메일").foregroundStyle(Theme.text) } icon: { Image(systemName: "person.crop.circle.fill").foregroundStyle(Theme.gold) }
                            Spacer()
                            Text(auth.email ?? "-").font(pd(12)).foregroundStyle(Theme.muted)
                        }
                        Button { auth.signOut(); fleet.role = .none; fleet.fleets = []; fleet.vehicles = []; Task { await adminStore.refresh(auth: auth) } } label: {
                            Label { Text("로그아웃").foregroundStyle(Theme.text) } icon: { Image(systemName: "arrow.right.square").foregroundStyle(Theme.silver) }
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            HStack { if deleting { ProgressView().controlSize(.small) }
                                Label("계정 삭제", systemImage: "trash.fill").foregroundStyle(.red) }
                        }.disabled(deleting)
                        if let e = deleteError { Text(e).font(pd(11)).foregroundStyle(.red) }
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
        .sheet(isPresented: $showShortcuts) { ShortcutsGuideView() }
        .sheet(isPresented: $showInbox, onDismiss: { Task { await adminStore.refresh(auth: auth) } }) { AdminInboxView(auth: auth) }
        .sheet(item: $legal) { doc in LegalTextView(title: doc.title, body_: doc.text) }
        .confirmationDialog("계정을 삭제할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("계정 삭제", role: .destructive) { Task { await deleteAccount() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("계정과 관련 데이터(조직·차량·기록·배정)가 영구 삭제되며 되돌릴 수 없어요.")
        }
        .task { await adminStore.refresh(auth: auth) }
        .onChange(of: auth.isAuthenticated) { _, _ in Task { await adminStore.refresh(auth: auth) } }
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
    private func deleteAccount() async {
        deleting = true; deleteError = nil; defer { deleting = false }
        let r = await auth.deleteAccount()
        if r.ok {
            fleet.role = .none; fleet.fleets = []; fleet.vehicles = []; fleet.assignments = []; fleet.members = []
            await adminStore.refresh(auth: auth)
        } else { deleteError = r.error }
    }

    private func requestReview() {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}
