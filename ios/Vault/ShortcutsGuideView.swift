import SwiftUI
import AppIntents

/// 카드 승인 문자를 아이폰 단축어로 받아 자동으로 기록을 추가하는 설정 가이드.
struct ShortcutsGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String)] = [
        ("단축어 앱 열기", "아래 버튼으로 단축어 앱을 열고 ‘자동화’ 탭 → ‘＋’를 누릅니다."),
        ("메시지 자동화 선택", "‘메시지’를 고르고, 카드사 번호(예: 15771577)를 ‘보낸 사람’에 넣은 뒤 ‘받았을 때’를 선택합니다."),
        ("즉시 실행 켜기", "‘실행 전 확인’을 끄면 문자가 오는 즉시 자동으로 기록됩니다."),
        ("금액·가맹점 추출", "동작 추가 → ‘텍스트에서 일치 항목 가져오기(정규식)’로 금액 `[0-9,]+원`, 가맹점명을 뽑아냅니다."),
        ("Wheelet 기록 추가", "동작 추가에서 ‘Wheelet: 지출 기록 추가’를 넣고, 금액·가맹점을 연결합니다. 종류는 ‘자동’으로 두면 주유소·충전소·정비소를 알아서 판별합니다."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 헤더
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "creditcard.fill").font(.system(size: 30)).foregroundStyle(Theme.gold)
                        Text("카드문자 자동입력")
                            .font(pd(20, .bold)).foregroundStyle(Theme.text)
                        Text("카드 승인 문자가 오면 아이폰 단축어가 금액·가맹점을 읽어 자동으로 차계부에 기록합니다. 한 번만 설정하면 됩니다.")
                            .font(pd(12.5)).foregroundStyle(Theme.muted).lineSpacing(3)
                    }
                    .padding(.top, 4)

                    // 단축어 추가 버튼 (앱의 인텐트를 단축어 앱에 노출)
                    ShortcutsLink()
                        .shortcutsLinkStyle(.automatic)
                        .frame(maxWidth: .infinity)

                    // 단계
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(i + 1)")
                                    .font(pd(13, .bold)).foregroundStyle(Theme.ink)
                                    .frame(width: 26, height: 26)
                                    .background(Theme.goldGradient).clipShape(Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(step.0).font(pd(14, .semibold)).foregroundStyle(Theme.text)
                                    Text(step.1).font(pd(12)).foregroundStyle(Theme.muted).lineSpacing(2)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))

                    // 단축어 앱 열기
                    Button {
                        if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                    } label: {
                        Label("단축어 앱 열기", systemImage: "arrow.up.forward.app.fill")
                            .font(pd(14, .semibold)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.goldGradient).clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // 안내
                    VStack(alignment: .leading, spacing: 6) {
                        Label("종류 ‘자동’은 GS칼텍스·SK에너지 등 주유소는 주유, 슈퍼차저·환경부 등은 충전, 블루핸즈·타이어점 등은 정비로 판별합니다.",
                              systemImage: "wand.and.stars").font(pd(11)).foregroundStyle(Theme.muted)
                        Label("기록은 현재 앱에서 선택된 차량에 저장됩니다. 여러 대면 앱에서 차량을 먼저 선택해 두세요.",
                              systemImage: "car.fill").font(pd(11)).foregroundStyle(Theme.muted)
                        Label("카드사마다 문자 형식이 달라 정규식은 본인 문자에 맞게 조정이 필요할 수 있습니다.",
                              systemImage: "info.circle").font(pd(11)).foregroundStyle(Theme.muted)
                    }
                    .padding(14)
                    .background(Theme.gold.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(20)
            }
            .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("자동입력 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
    }
}
