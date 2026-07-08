import SwiftUI

/// Fleet 로그인/회원가입 (Supabase Auth).
struct AuthView: View {
    @ObservedObject var auth: AuthService
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?
    @State private var info: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "building.2.crop.circle.fill").font(.system(size: 44)).foregroundStyle(Theme.gold).padding(.top, 30)
                Text(isSignUp ? "관리자 계정 만들기" : "관리자 로그인").font(gm(19, .bold))
                Text("기업용 Fleet은 계정별로 데이터가 안전하게 분리됩니다.")
                    .font(pd(12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 24)

                VStack(spacing: 10) {
                    TextField("이메일", text: $email)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress).textContentType(.emailAddress)
                        .padding(13).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                    SecureField("비밀번호 (6자 이상)", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .padding(13).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                }
                .padding(.horizontal, 20)

                if let error { Text(error).font(pd(11)).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal, 20) }
                if let info { Text(info).font(pd(11)).foregroundStyle(Theme.green).multilineTextAlignment(.center).padding(.horizontal, 20) }

                Button { Task { await submit() } } label: {
                    HStack { if loading { ProgressView().controlSize(.small).tint(Theme.ink) }
                        Text(isSignUp ? "가입하고 시작" : "로그인").font(pd(15, .semibold)) }
                        .foregroundStyle(Theme.ink).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.goldGradient).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(loading || email.isEmpty || password.count < 6)
                .padding(.horizontal, 20)

                Button { isSignUp.toggle(); error = nil; info = nil } label: {
                    Text(isSignUp ? "이미 계정이 있어요 · 로그인" : "계정이 없어요 · 가입하기")
                        .font(pd(12)).foregroundStyle(Theme.gold)
                }
            }
        }
        .background(Theme.bgTop.ignoresSafeArea())
        .foregroundStyle(Theme.text)
    }

    private func submit() async {
        loading = true; error = nil; info = nil; defer { loading = false }
        let mail = email.trimmingCharacters(in: .whitespaces)
        if isSignUp {
            let r = await auth.signUp(email: mail, password: password)
            if r.needsConfirm { info = L("확인 메일을 보냈어요. 메일 인증 후 로그인해 주세요.") }
            else if !r.ok { error = r.error }
        } else {
            let r = await auth.signIn(email: mail, password: password)
            if !r.ok { error = r.error }
        }
    }
}
