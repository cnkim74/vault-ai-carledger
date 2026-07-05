import SwiftUI
import AuthenticationServices

/// 프로필 입력 시트 — 이름 직접 입력 또는 Apple로 계속하기.
struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var profile: ProfileStore
    @State private var name: String
    @State private var appleNote: String?

    init(profile: ProfileStore) {
        self.profile = profile
        _name = State(initialValue: profile.name)
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
    }
}
