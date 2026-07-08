import SwiftUI

/// 관리자 문의함 — 앱 안에서 1:1 문의를 확인/처리(Supabase 대시보드 불필요).
/// 관리자(app_admins에 등록된 계정)만 RLS로 조회/수정 가능.
struct AdminInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var auth: AuthService
    @State private var items: [Inquiry] = []
    @State private var loading = false
    @State private var showHandled = false

    struct Inquiry: Codable, Identifiable {
        let id: UUID
        let email: String?
        let message: String
        let app_version: String?
        let created_at: String
        var handled: Bool
        var date: Date { ISO8601DateFormatter().date(from: created_at) ?? Date() }
    }

    private var visible: [Inquiry] { showHandled ? items : items.filter { !$0.handled } }
    private var pendingCount: Int { items.filter { !$0.handled }.count }

    var body: some View {
        NavigationStack {
            Group {
                if loading && items.isEmpty {
                    ProgressView().tint(Theme.gold).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visible.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.system(size: 30)).foregroundStyle(Theme.muted)
                        Text(showHandled ? "문의가 없어요" : "새 문의가 없어요").font(pd(13)).foregroundStyle(Theme.muted)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(visible) { row($0) }
                        }.padding(16)
                    }
                }
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle(pendingCount > 0 ? "문의함 (\(pendingCount))" : "문의함")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle("처리완료 포함", isOn: $showHandled)
                        Button { Task { await load() } } label: { Label("새로고침", systemImage: "arrow.clockwise") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .tint(Theme.gold).preferredColorScheme(.dark)
        .task { await load() }
    }

    private func row(_ q: Inquiry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Self.df.string(from: q.date)).font(pd(10.5)).foregroundStyle(Theme.muted)
                Spacer()
                if q.handled {
                    Text("처리완료").font(pd(9.5, .bold)).foregroundStyle(Theme.green)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Theme.green.opacity(0.5), lineWidth: 1))
                }
            }
            Text(q.message).font(pd(13)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let e = q.email, !e.isEmpty {
                    Button { reply(to: e) } label: {
                        Label(e, systemImage: "arrowshape.turn.up.left.fill").font(pd(11, .semibold)).foregroundStyle(Theme.gold)
                    }
                } else {
                    Text("이메일 없음").font(pd(11)).foregroundStyle(Theme.muted2)
                }
                Spacer()
                if let v = q.app_version { Text("v\(v)").font(pd(9.5)).foregroundStyle(Theme.muted2) }
                Button { Task { await setHandled(q, !q.handled) } } label: {
                    Text(q.handled ? "미처리로" : "처리완료")
                        .font(pd(11, .semibold)).foregroundStyle(q.handled ? Theme.muted : Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(q.handled ? AnyShapeStyle(Color.white.opacity(0.06)) : AnyShapeStyle(Theme.goldGradient))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(13).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private func reply(to email: String) {
        let subject = "Wheelet 문의 답변".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(email)?subject=\(subject)") { UIApplication.shared.open(url) }
    }

    // MARK: 네트워킹 (관리자 토큰)
    private func load() async {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, let token = await auth.validToken() else { return }
        loading = true; defer { loading = false }
        var comps = URLComponents(url: base.appendingPathComponent("rest/v1/inquiries"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "select", value: "*"), .init(name: "order", value: "created_at.desc")]
        var req = URLRequest(url: comps.url!)
        req.setValue(key, forHTTPHeaderField: "apikey"); req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let rows = try? JSONDecoder().decode([Inquiry].self, from: data) {
            items = rows
        }
    }

    private func setHandled(_ q: Inquiry, _ value: Bool) async {
        guard let base = Secrets.supabaseURL, let key = Secrets.supabaseKey, let token = await auth.validToken() else { return }
        var comps = URLComponents(url: base.appendingPathComponent("rest/v1/inquiries"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "id", value: "eq.\(q.id.uuidString.lowercased())")]
        var req = URLRequest(url: comps.url!); req.httpMethod = "PATCH"
        req.setValue(key, forHTTPHeaderField: "apikey"); req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONEncoder().encode(["handled": value])
        _ = try? await URLSession.shared.data(for: req)
        if let i = items.firstIndex(where: { $0.id == q.id }) { items[i].handled = value }
    }

    private static let df: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "M/d HH:mm"; return f }()
}
