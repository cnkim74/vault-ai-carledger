import SwiftUI
import AuthenticationServices

/// 프로필 입력 시트 — 이름 직접 입력 또는 Apple로 계속하기.
struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var profile: ProfileStore
    @State private var name: String
    @State private var appleNote: String?
    @State private var showLangRestart = false

    // (표시명, AppleLanguages 코드 · nil=시스템 기본값)
    private let languages: [(String, String?)] = [
        ("시스템 기본값", nil), ("한국어", "ko"), ("English", "en"),
        ("日本語", "ja"), ("简体中文", "zh-Hans"),
    ]

    init(profile: ProfileStore) {
        self.profile = profile
        _name = State(initialValue: profile.name)
    }

    private var currentLangName: String {
        let saved = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first
        // 저장된 override가 목록에 있으면 그 이름, 없으면 시스템 기본값
        if let saved, let m = languages.first(where: { $0.1 != nil && saved.hasPrefix($0.1!) }) {
            return m.0
        }
        return L("시스템 기본값")
    }

    private func setLanguage(_ code: String?) {
        if let code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        showLangRestart = true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Circle()
                    .fill(Theme.goldGradient)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Text(name.isEmpty ? "ME" : String(name.prefix(2)))
                            .font(gm(22, .bold))
                            .foregroundStyle(Theme.ink)
                    )
                    .padding(.top, 12)

                Text("어떻게 불러드릴까요?")
                    .font(pd(15, .semibold))
                    .foregroundStyle(Theme.text)

                TextField("이름", text: $name)
                    .font(pd(15))
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))

                // Apple로 계속하기 — 최초 인증 시 이름 자동 입력
                SignInWithAppleButton(.continue) { req in
                    req.requestedScopes = [.fullName]
                } onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        if let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                           let given = cred.fullName?.givenName, !given.isEmpty {
                            name = given
                            appleNote = nil
                        } else {
                            appleNote = "Apple 계정에 이름이 없어요. 직접 입력해 주세요."
                        }
                    case .failure:
                        appleNote = "Apple 로그인을 사용할 수 없어요. 이름을 직접 입력해 주세요."
                    }
                }
                .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let note = appleNote {
                    Text(note).font(pd(11)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }

                // 언어 선택
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "globe").font(.system(size: 14)).foregroundStyle(Theme.gold)
                        Text("언어").font(pd(14)).foregroundStyle(Theme.text)
                    }
                    Spacer()
                    Menu {
                        ForEach(languages, id: \.0) { item in
                            Button(item.0) { setLanguage(item.1) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentLangName).font(pd(14, .semibold)).foregroundStyle(Theme.gold)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(14)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))

                Spacer()
            }
            .padding(20)
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationTitle("프로필")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        profile.save(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .alert("언어 변경", isPresented: $showLangRestart) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("언어를 변경했어요. 앱을 완전히 종료 후 다시 실행하면 적용됩니다.")
        }
    }
}
