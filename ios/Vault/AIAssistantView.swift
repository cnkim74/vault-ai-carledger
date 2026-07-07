import SwiftUI

/// AI 어시스턴트 — 내 차량·기록 데이터 기반 질의응답 + 절약 플랜.
struct AIAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore
    /// 열자마자 자동 실행할 프롬프트 (절약 플랜 등). 없으면 빈 화면.
    var initialPrompt: String?

    struct Msg: Identifiable { let id = UUID(); let role: String; let text: String }
    @State private var messages: [Msg] = []
    @State private var input = ""
    @State private var loading = false
    @State private var started = false

    private let suggestions = ["이번 달 지출 분석해줘", "절약 플랜 알려줘", "연비/전비 어때?", "다음 정비는 언제야?"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty && !loading {
                                emptyState
                            }
                            ForEach(messages) { bubble($0) }
                            if loading {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small).tint(Theme.gold)
                                    Text("생각 중…").font(pd(12)).foregroundStyle(Theme.muted)
                                }
                                .id("loading")
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                    }
                }
                inputBar
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("AI 어시스턴트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .task {
            guard !started else { return }
            started = true
            if let p = initialPrompt { await send(p) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("무엇이든 물어보세요").font(pd(14, .semibold)).foregroundStyle(Theme.silver)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button { Task { await send(L(s)) } } label: {
                        Text(L(s)).font(pd(12)).foregroundStyle(Theme.gold)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Theme.gold.opacity(0.12)).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bubble(_ m: Msg) -> some View {
        HStack {
            if m.role == "user" { Spacer(minLength: 40) }
            Text(m.text)
                .font(pd(13))
                .foregroundStyle(m.role == "user" ? Theme.ink : Theme.text)
                .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
                .background(m.role == "user" ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.card))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(m.role == "user" ? Color.clear : Theme.cardBorder, lineWidth: 1))
            if m.role != "user" { Spacer(minLength: 40) }
        }
        .id(m.id)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("메시지 입력", text: $input, axis: .vertical)
                .font(pd(13)).foregroundStyle(Theme.text)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit { let t = input; Task { await send(t) } }
            Button {
                let t = input; Task { await send(t) }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 26))
                    .foregroundStyle(input.trimmingCharacters(in: .whitespaces).isEmpty || loading ? Theme.muted : Theme.gold)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || loading)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.cardAlt)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.white.opacity(0.06)), alignment: .top)
    }

    private func send(_ text: String) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !loading else { return }
        input = ""
        messages.append(Msg(role: "user", text: q))
        loading = true; defer { loading = false }

        // 대화 이력을 하나의 사용자 메시지로 (다중 턴 맥락 유지)
        let convo = messages.map { ($0.role == "user" ? "Q: " : "A: ") + $0.text }.joined(separator: "\n")
        let answer = await AIProxy.complete(system: Self.systemPrompt(store: store), user: convo, maxTokens: 600)
        messages.append(Msg(role: "ai", text: answer ?? L("답변을 가져오지 못했어요. 잠시 후 다시 시도해 주세요.")))
    }

    private static func systemPrompt(store: VaultStore) -> String {
        let v = store.vehicle
        let df = DateFormatter(); df.dateFormat = "M/d"
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
        var ctx: [String] = []
        ctx.append("오늘: \(day.string(from: Date()))")
        ctx.append("차량: \(v.name) (\(v.vehicleCategory.label), \(v.fuelType)), 누적 \(v.odometerKm)km")
        if let s = store.monthlySpend {
            ctx.append("이번 달 지출: \(s.total)원 (충전 \(s.charge)/주유 \(s.fuel)/정비 \(s.maintenance)/기타 \(s.other)), 지난달 \(s.prevTotal)원")
        }
        if let p = v.leaseProjection() {
            ctx.append("약정: \(p.drivenKm)/\(p.limitKm)km, 적정대비 \(p.paceRatioPct)%, 잔여 \(max(0,p.daysRemaining))일")
        }
        if !store.records.isEmpty {
            ctx.append("최근 기록:")
            for r in store.records.prefix(10) {
                var parts = ["[\(df.string(from: r.occurredAt))] \(r.title)"]
                if let a = r.amountWon { parts.append("\(a)원") }
                if let d = r.distanceKm { parts.append("\(d)km") }
                ctx.append(parts.joined(separator: " · "))
            }
        }
        return """
        너는 차계부 앱 Wheelet의 AI 비서다. 아래 사용자 차량·기록 데이터를 근거로 질문에 정확하고 간결하게(2~4문장) 답한다. \
        금액·거리 등 숫자는 반드시 제공된 데이터에서 계산하고, 데이터에 없는 값은 지어내지 않는다. \
        절약 플랜을 요청하면 실천 가능한 팁 2~3개를 구체 숫자와 함께 제시한다.

        [데이터]
        \(ctx.joined(separator: "\n"))
        """
    }
}
