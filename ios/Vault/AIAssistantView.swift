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
    @StateObject private var speech = SpeechRecognizer()
    @StateObject private var chats = ChatStore()
    @StateObject private var speaker = Speaker()
    @State private var currentID = UUID()
    @State private var convTitle: String?
    @State private var showHistory = false

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    Button { newConversation() } label: { Image(systemName: "square.and.pencil") }
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .task {
            guard !started else { return }
            started = true
            if let p = initialPrompt { await send(p) }
        }
        .onChange(of: speech.transcript) { _, t in if speech.isRecording { input = t } }
        .onDisappear { speaker.stop(); speech.stop() }
        .sheet(isPresented: $showHistory) {
            ChatHistoryView(chats: chats) { conv in
                loadConversation(conv)
                showHistory = false
            }
        }
    }

    private func newConversation() {
        speech.stop(); speaker.stop()
        messages = []; input = ""; currentID = UUID(); convTitle = nil
    }
    private func loadConversation(_ conv: Conversation) {
        speech.stop(); speaker.stop()
        currentID = conv.id; convTitle = conv.title
        messages = conv.messages.map { Msg(role: $0.role, text: $0.text) }
    }
    private func saveCurrent() {
        guard !messages.isEmpty else { return }
        let fallback = messages.first(where: { $0.role == "user" })?.text ?? L("대화")
        let title = convTitle ?? String(fallback.prefix(40))
        chats.upsert(id: currentID, title: title,
                     messages: messages.map { StoredMsg(role: $0.role, text: $0.text) })
    }

    /// 첫 문답을 6단어 이내 제목으로 요약
    private static func summarizeTitle(_ q: String, _ a: String) async -> String? {
        let sys = "다음 대화를 6단어 이내의 아주 짧은 제목으로 요약한다. 따옴표·마침표 없이 제목만 출력한다."
        let t = await AIProxy.complete(system: sys, user: "질문: \(q)\n답변: \(a)", maxTokens: 30)
        let clean = t?.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        return (clean?.isEmpty == false) ? clean : nil
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
        HStack(alignment: .top) {
            if m.role == "user" { Spacer(minLength: 40) }
            VStack(alignment: m.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(m.text)
                    .font(pd(13))
                    .foregroundStyle(m.role == "user" ? Theme.ink : Theme.text)
                    .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
                    .background(m.role == "user" ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.card))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(m.role == "user" ? Color.clear : Theme.cardBorder, lineWidth: 1))
                // AI 답변: 음성 읽어주기
                if m.role != "user" {
                    Button { speaker.toggle(m.id, text: m.text) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: speaker.speakingID == m.id ? "stop.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 10))
                            Text(speaker.speakingID == m.id ? "정지" : "듣기").font(pd(10))
                        }
                        .foregroundStyle(speaker.speakingID == m.id ? Theme.gold : Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
            if m.role != "user" { Spacer(minLength: 40) }
        }
        .id(m.id)
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            if speech.isRecording {
                HStack(spacing: 6) {
                    Circle().fill(Theme.red).frame(width: 7, height: 7)
                    Text("듣는 중… 마이크를 다시 누르면 완료").font(pd(10.5)).foregroundStyle(Theme.muted)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8)
            } else if speech.denied {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Theme.orange)
                    Text("설정에서 마이크·음성 인식 권한을 켜주세요.").font(pd(10.5)).foregroundStyle(Theme.muted)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
            HStack(spacing: 10) {
                // 음성 입력 (녹음 시작/종료 토글)
                Button { speech.toggle() } label: {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(speech.isRecording ? Theme.red : Theme.silver)
                }
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
        }
        .background(Theme.cardAlt)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.white.opacity(0.06)), alignment: .top)
    }

    private func send(_ text: String) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !loading else { return }
        if speech.isRecording { speech.stop() }
        input = ""
        messages.append(Msg(role: "user", text: q))
        loading = true; defer { loading = false }

        // 대화 이력을 하나의 사용자 메시지로 (다중 턴 맥락 유지)
        let convo = messages.map { ($0.role == "user" ? "Q: " : "A: ") + $0.text }.joined(separator: "\n")
        let answer = await AIProxy.complete(system: Self.systemPrompt(store: store), user: convo, maxTokens: 600)
        let reply = groupInlineNumbers(answer ?? L("답변을 가져오지 못했어요. 잠시 후 다시 시도해 주세요."))
        messages.append(Msg(role: "ai", text: reply))
        // 첫 문답이면 제목 자동 요약
        if convTitle == nil, answer != nil, messages.count == 2 {
            convTitle = await Self.summarizeTitle(q, reply)
        }
        saveCurrent()   // 로컬 + Supabase 저장
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

/// 저장된 대화 목록
struct ChatHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var chats: ChatStore
    var onSelect: (Conversation) -> Void

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "M/d HH:mm"; return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if chats.conversations.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock").font(.system(size: 28)).foregroundStyle(Theme.muted)
                        Text("저장된 대화가 없어요").font(pd(13)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(chats.conversations) { conv in
                            Button { onSelect(conv) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conv.title).font(pd(13.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text(Self.df.string(from: conv.updatedAt)).font(pd(10.5)).foregroundStyle(Theme.muted)
                                }
                            }
                            .listRowBackground(Theme.card)
                        }
                        .onDelete { idx in idx.map { chats.conversations[$0].id }.forEach(chats.delete) }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .navigationTitle("대화 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
    }
}
