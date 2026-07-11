import SwiftUI

/// 충전 리포트 — 총 충전량·지출, 일별 추이, 장소별 분류, 휘발유 등가 절약을 프리미엄하게 시각화.
/// 데이터는 충전 기록(테슬라 임포트 + 수동)에서 집계. kWh는 제목에서 파싱.
struct ChargingReportView: View {
    @ObservedObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    enum Period: String, CaseIterable, Identifiable {
        case d31 = "최근 31일", all = "전체"
        var id: String { rawValue }
        var days: Int? { self == .d31 ? 31 : nil }
    }
    @State private var period: Period = .d31

    enum ReportTab: String, CaseIterable, Identifiable {
        case summary = "요약", monthly = "월별"
        var id: String { rawValue }
    }
    @State private var tab: ReportTab = .summary

    // 전비/연비/유가 가정 (절약 추정)
    private let kmPerKwh = 5.0
    private let kmPerL = 12.0
    private let wonPerL = 1700.0

    private var charges: [VaultRecord] {
        let all = store.records.filter { $0.kind == .charge }
        guard let d = period.days else { return all }
        let cutoff = Calendar.current.date(byAdding: .day, value: -d, to: Date()) ?? .distantPast
        return all.filter { $0.occurredAt >= cutoff }
    }

    private var totalKwh: Double { charges.reduce(0) { $0 + kwh(of: $1) } }
    private var totalSpend: Int { charges.reduce(0) { $0 + ($1.amountWon ?? 0) } }
    private var sessionCount: Int { charges.count }

    private var kmAdded: Double { totalKwh * kmPerKwh }
    private var gasEquivalent: Int { Int((kmAdded / kmPerL) * wonPerL) }
    private var saved: Int { max(0, gasEquivalent - totalSpend) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("", selection: $tab) {
                        ForEach(ReportTab.allCases) { Text(L($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case .summary:
                        periodPicker
                        heroTiles
                        if !charges.isEmpty {
                            dailyChart
                            spotBreakdown
                            savingsCard
                        } else {
                            emptyState
                        }
                        disclaimer
                    case .monthly:
                        monthlyView
                    }
                }
                .padding(20)
            }
            .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("충전 리포트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
    }

    // MARK: 기간 선택
    private var periodPicker: some View {
        Picker("기간", selection: $period) {
            ForEach(Period.allCases) { Text(L($0.rawValue)).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: 총 충전량 / 총 지출
    private var heroTiles: some View {
        HStack(spacing: 12) {
            tile(title: "총 충전량", value: grouped(Int(totalKwh.rounded())), unit: "kWh", accent: Theme.gold)
            tile(title: "총 지출", value: won(totalSpend), unit: nil, accent: Theme.green)
        }
    }

    private func tile(title: String, value: String, unit: String?, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(title)).font(pd(11.5)).foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(gm(26, .bold)).foregroundStyle(Theme.text)
                if let unit { Text(unit).font(pd(13, .semibold)).foregroundStyle(Theme.muted) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: 일별 추이 (최근 31일)
    private var dailyChart: some View {
        let bars = dailyKwh()
        let maxV = max(bars.map(\.kwh).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("일별 충전량").font(pd(13, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text(verbatim: "\(Int(maxV.rounded())) kWh").font(pd(10.5)).foregroundStyle(Theme.muted)
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(bars) { b in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(b.kwh > 0 ? Theme.goldGradient : LinearGradient(colors: [Theme.cardAlt, Theme.cardAlt], startPoint: .top, endPoint: .bottom))
                        .frame(height: max(3, CGFloat(b.kwh / maxV) * 96))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
            HStack {
                Text("31일 전").font(pd(9.5)).foregroundStyle(Theme.muted)
                Spacer()
                Text("오늘").font(pd(9.5)).foregroundStyle(Theme.muted)
            }
        }
        .padding(16)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: 장소별 분류
    private var spotBreakdown: some View {
        let g = spotGroups()
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            spotCell(.home, g)
            spotCell(.supercharger, g)
            spotCell(.work, g)
            spotCell(.other, g)
        }
    }

    private func spotCell(_ s: ChargeSpot, _ g: [ChargeSpot: Double]) -> some View {
        let v = g[s] ?? 0
        let pct = totalKwh > 0 ? Int((v / totalKwh * 100).rounded()) : 0
        return HStack(spacing: 10) {
            Circle().fill(s.color.opacity(0.18)).frame(width: 34, height: 34)
                .overlay(Image(systemName: s.icon).font(.system(size: 14)).foregroundStyle(s.color))
            VStack(alignment: .leading, spacing: 2) {
                Text(L(s.label)).font(pd(12, .semibold)).foregroundStyle(Theme.text)
                Text(verbatim: "\(grouped(Int(v.rounded()))) kWh · \(pct)%").font(pd(10.5)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: 휘발유 등가 절약
    private var savingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("휘발유차 대비 절약").font(pd(13, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "leaf.fill").font(.system(size: 13)).foregroundStyle(Theme.green)
            }
            Text(won(saved)).font(gm(30, .bold)).foregroundStyle(Theme.green)

            // 비교 막대
            let gas = max(gasEquivalent, 1)
            VStack(spacing: 8) {
                compareBar("전기 충전", totalSpend, gas, Theme.green)
                compareBar("휘발유 등가", gasEquivalent, gas, Theme.muted2)
            }
            HStack(spacing: 16) {
                miniStat("추가 주행(추정)", "\(grouped(Int(kmAdded.rounded())))km")
                miniStat("충전 세션", "\(sessionCount)회")
            }
        }
        .padding(16)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func compareBar(_ label: String, _ value: Int, _ maxV: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L(label)).font(pd(11)).foregroundStyle(Theme.muted)
                Spacer()
                Text(won(value)).font(gm(12, .semibold)).foregroundStyle(Theme.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cardAlt).frame(height: 8)
                    Capsule().fill(color).frame(width: max(6, geo.size.width * CGFloat(value) / CGFloat(maxV)), height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L(label)).font(pd(10)).foregroundStyle(Theme.muted)
            Text(value).font(gm(15, .semibold)).foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.car").font(.system(size: 34)).foregroundStyle(Theme.muted)
            Text("아직 충전 기록이 없어요").font(pd(14, .semibold)).foregroundStyle(Theme.text)
            Text("충전 기록을 추가하거나 테슬라에서 가져오면\n여기에 리포트가 만들어져요.")
                .font(pd(11.5)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private var disclaimer: some View {
        Text(verbatim: L("절약·주행은 추정치예요 (전비 5.0km/kWh · 연비 12km/L · 휘발유 1,700원/L 기준)."))
            .font(pd(10)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: 월별 탭
    private var monthlyView: some View {
        let stats = monthlyStats()
        let maxKwh = max(stats.map(\.kwh).max() ?? 1, 1)
        return VStack(spacing: 12) {
            if stats.isEmpty {
                emptyState
            } else {
                // 전체 합계 요약
                HStack(spacing: 12) {
                    tile(title: "총 충전량", value: grouped(Int(stats.reduce(0) { $0 + $1.kwh }.rounded())), unit: "kWh", accent: Theme.gold)
                    tile(title: "총 지출", value: won(stats.reduce(0) { $0 + $1.won }), unit: nil, accent: Theme.green)
                }
                // 월별 카드
                ForEach(stats) { m in
                    VStack(spacing: 8) {
                        HStack {
                            Text(m.label).font(pd(13, .semibold)).foregroundStyle(Theme.text)
                            Spacer()
                            Text(verbatim: "\(grouped(Int(m.kwh.rounded()))) kWh").font(gm(13, .semibold)).foregroundStyle(Theme.gold)
                        }
                        // kWh 바
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.cardAlt).frame(height: 7)
                                Capsule().fill(Theme.goldGradient)
                                    .frame(width: max(6, geo.size.width * CGFloat(m.kwh / maxKwh)), height: 7)
                            }
                        }
                        .frame(height: 7)
                        HStack {
                            Text(verbatim: String(format: L("%d회 충전"), m.count)).font(pd(10.5)).foregroundStyle(Theme.muted)
                            Spacer()
                            Text(won(m.won)).font(pd(11.5, .medium)).foregroundStyle(Theme.text)
                        }
                    }
                    .padding(14)
                    .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                disclaimer
            }
        }
    }

    private struct MonthStat: Identifiable {
        let id: String; let label: String; let kwh: Double; let won: Int; let count: Int; let sort: Date
    }

    private func monthlyStats() -> [MonthStat] {
        let cal = Calendar.current
        var map: [String: (kwh: Double, won: Int, count: Int, date: Date)] = [:]
        for r in store.records where r.kind == .charge {
            let comps = cal.dateComponents([.year, .month], from: r.occurredAt)
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            let mStart = cal.date(from: comps) ?? r.occurredAt
            var e = map[key] ?? (0, 0, 0, mStart)
            e.kwh += kwh(of: r); e.won += (r.amountWon ?? 0); e.count += 1
            map[key] = e
        }
        return map.map { (_, v) in
            let y = cal.component(.year, from: v.date), mo = cal.component(.month, from: v.date)
            return MonthStat(id: String(format: "%04d-%02d", y, mo),
                             label: String(format: L("%d년 %d월"), y, mo),
                             kwh: v.kwh, won: v.won, count: v.count, sort: v.date)
        }
        .sorted { $0.sort > $1.sort }
    }

    // MARK: - 집계 헬퍼

    private func kwh(of r: VaultRecord) -> Double {
        guard let range = r.title.range(of: #"([0-9][0-9,\.]*)\s*kWh"#, options: [.regularExpression, .caseInsensitive]) else { return 0 }
        let num = r.title[range]
            .replacingOccurrences(of: "kWh", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(num) ?? 0
    }

    private struct DayBar: Identifiable { let id: Int; let kwh: Double }

    private func dailyKwh() -> [DayBar] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var buckets = Array(repeating: 0.0, count: 31)
        for r in store.records where r.kind == .charge {
            let day = cal.startOfDay(for: r.occurredAt)
            let diff = cal.dateComponents([.day], from: day, to: today).day ?? 99
            if diff >= 0 && diff < 31 { buckets[30 - diff] += kwh(of: r) }
        }
        return buckets.enumerated().map { DayBar(id: $0.offset, kwh: $0.element) }
    }

    enum ChargeSpot: CaseIterable {
        case home, supercharger, work, other
        var label: String {
            switch self { case .home: return "홈"; case .supercharger: return "수퍼차저"; case .work: return "회사"; case .other: return "기타" }
        }
        var icon: String {
            switch self { case .home: return "house.fill"; case .supercharger: return "bolt.fill"; case .work: return "briefcase.fill"; case .other: return "powerplug.fill" }
        }
        var color: Color {
            switch self { case .home: return Color(hex: 0x4F8DF7); case .supercharger: return Theme.red; case .work: return Theme.orange; case .other: return Theme.silver }
        }
    }

    private func spot(_ r: VaultRecord) -> ChargeSpot {
        let l = (r.location ?? "").lowercased()
        let t = (r.tag ?? "").lowercased()
        if r.title.contains("슈퍼차저") || l.contains("슈퍼차저") || l.contains("supercharger") || t.contains("tesla") { return .supercharger }
        if l.contains("집") || l.contains("자택") || l.contains("home") || l.contains("아파트") || l.contains("빌라") || l.contains("우리집") { return .home }
        if l.contains("회사") || l.contains("직장") || l.contains("사무실") || l.contains("work") || l.contains("오피스") { return .work }
        return .other
    }

    private func spotGroups() -> [ChargeSpot: Double] {
        var g: [ChargeSpot: Double] = [:]
        for r in charges { g[spot(r), default: 0] += kwh(of: r) }
        return g
    }
}
