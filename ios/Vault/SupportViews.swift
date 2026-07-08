import SwiftUI

/// 1:1 문의 폼 — Supabase inquiries 테이블에 저장(익명 insert).
/// 개발자는 Supabase 대시보드 Table Editor > inquiries 에서 바로 확인.
struct InquiryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var message = ""
    @State private var sending = false
    @State private var done = false
    @State private var error: String?

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Group {
                if done { sentState } else { form }
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("1:1 문의").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .tint(Theme.gold).preferredColorScheme(.dark)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("궁금하거나 불편한 점을 남겨주세요. 답변받을 이메일을 함께 적어주시면 회신드려요.")
                    .font(pd(12)).foregroundStyle(Theme.muted)

                VStack(alignment: .leading, spacing: 6) {
                    Text("이메일 (선택)").font(pd(11, .semibold)).foregroundStyle(Theme.silver)
                    TextField("회신받을 이메일", text: $email)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                        .padding(13).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("문의 내용").font(pd(11, .semibold)).foregroundStyle(Theme.silver)
                    TextEditor(text: $message)
                        .frame(minHeight: 150).scrollContentBackground(.hidden)
                        .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                }

                if let error { Text(error).font(pd(11)).foregroundStyle(.red) }

                Button { Task { await send() } } label: {
                    HStack { if sending { ProgressView().controlSize(.small).tint(Theme.ink) }
                        Text("보내기").font(pd(15, .semibold)) }
                        .foregroundStyle(Theme.ink).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.goldGradient).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text(verbatim: "앱 버전 \(appVersion)").font(pd(9.5)).foregroundStyle(Theme.muted2)
            }
            .padding(20)
        }
    }

    private var sentState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(Theme.green)
            Text("문의가 접수됐어요").font(gm(18, .bold))
            Text("빠르게 확인하고, 이메일을 남기셨다면 회신드릴게요.")
                .font(pd(12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Spacer()
            Button { dismiss() } label: {
                Text("확인").font(pd(15, .semibold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.goldGradient).clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(24)
    }

    private func send() async {
        sending = true; error = nil; defer { sending = false }
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, !key.isEmpty else {
            error = L("전송 설정이 없어요. 잠시 후 다시 시도해 주세요."); return
        }
        struct Body: Encodable { let email: String?; let message: String; let app_version: String; let platform: String }
        let body = Body(email: email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email,
                        message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                        app_version: appVersion, platform: "ios")
        var req = URLRequest(url: base.appendingPathComponent("rest/v1/inquiries"))
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONEncoder().encode(body)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                error = L("전송에 실패했어요. 잠시 후 다시 시도해 주세요."); return
            }
            done = true
        } catch { self.error = L("전송에 실패했어요. 잠시 후 다시 시도해 주세요.") }
    }
}

/// 개인정보처리방침 / 이용약관 인앱 표시 (외부 링크 없이 앱 내 제공).
struct LegalTextView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let body_: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(body_).font(pd(12.5)).foregroundStyle(Theme.text).lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .tint(Theme.gold).preferredColorScheme(.dark)
    }
}

/// 법적 고지 원문 (배포 전 사업자 정보·연락처로 최종 검토 필요).
enum LegalText {
    static let privacy = """
    Wheelet 개인정보처리방침

    최종 개정일: 2026-07-08

    Wheelet(이하 "앱")은 이용자의 개인정보를 중요하게 생각하며, 관련 법령을 준수합니다.

    1. 수집하는 정보
    · 차량 정보: 제조사·모델·연식·연료·주행거리·번호판(선택)
    · 이용 기록: 주유·충전·정비·주행 등 이용자가 입력하거나 자동 연동으로 수집된 기록
    · 선택 정보: 문의 시 이메일, 차량 사진
    · 자동 연동(선택): 테슬라/차량 API·OBD 동글 연결 시 배터리·주행거리 등
    · 위치: 날씨·주변 검색에 사용되며 기기 내에서 처리됩니다

    2. 이용 목적
    · 차계부 기능 제공, 통계·AI 인사이트 생성, 서비스 개선 및 문의 응대

    3. 처리 위탁 및 제3자
    · 데이터 저장·인증: Supabase
    · AI 분석: Anthropic(Claude) — 분석에 필요한 최소 정보만 전송
    · 날씨·지도: 해당 서비스 제공사
    위 업체는 각사의 정책에 따라 정보를 처리하며, 앱은 이용자 정보를 판매하지 않습니다.

    4. 보관 및 파기
    · 서비스 이용 기간 동안 보관하며, 이용자가 삭제하거나 탈퇴 시 지체 없이 파기합니다.

    5. 이용자 권리
    · 이용자는 자신의 정보 열람·수정·삭제를 요청할 수 있습니다. 앱 내 문의로 요청해 주세요.

    6. 문의처
    · 앱 내 [1:1 문의]로 연락 주시면 신속히 처리합니다.

    ※ 본 방침은 서비스 정책 변경에 따라 갱신될 수 있으며, 앱 내 공지합니다.
    """

    static let terms = """
    Wheelet 이용약관

    최종 개정일: 2026-07-08

    제1조 (목적)
    본 약관은 Wheelet(이하 "앱")이 제공하는 서비스의 이용 조건 및 절차를 규정합니다.

    제2조 (서비스 내용)
    앱은 차량 기록 관리, 통계·AI 인사이트, 자동 연동(선택), 기업용 차량 관리 등을 제공합니다.

    제3조 (요금)
    · 기본 기능은 무료로 제공됩니다.
    · 자동 입력·자동 연동·중고 시세·리포트 등 일부 기능은 유료 구독(프리미엄)으로 제공됩니다.
    · 기업용(Fleet)은 별도 요금제로 제공됩니다.
    · 구독 결제·갱신·환불은 각 앱 마켓(App Store/Play)의 정책을 따릅니다.

    제4조 (이용자의 의무)
    · 이용자는 정확한 정보를 입력하며, 타인의 권리를 침해하지 않아야 합니다.

    제5조 (면책)
    · 앱이 제공하는 AI 추정·시세·예측은 참고용이며, 정확성을 보장하지 않습니다.
    · 자동 연동 데이터는 차량·기기·통신 환경에 따라 오차가 있을 수 있습니다.
    · 앱은 이용자의 판단과 사용으로 발생한 손해에 대해 책임을 지지 않습니다.

    제6조 (지식재산권)
    · 앱과 관련 콘텐츠의 권리는 제공자에게 있으며, 무단 복제·배포를 금합니다.

    제7조 (준거법)
    · 본 약관은 대한민국 법령에 따라 해석됩니다.

    ※ 본 약관은 변경될 수 있으며, 변경 시 앱 내 공지합니다.
    """
}
