import SwiftUI

/// 1b 브리핑형 — AI 브리핑 + 지출 중심 레저
struct BriefingView: View {
    @ObservedObject var store: VaultStore
    @ObservedObject var insight: InsightService
    @State private var showChecklist = false

    private var shortName: String {
        store.vehicle.name.split(separator: " ").prefix(2).joined(separator: " ")
    }

    /// 실제 데이터 기반 브리핑 문구. AI 인사이트 우선, 없으면 실데이터 요약, 그것도 없으면 안내.
    private var briefingText: String {
        if let tip = insight.tip, !tip.isEmpty { return tip }
        var parts: [String] = []
        if let s = store.monthlySpend { parts.append(String(format: L("이번 달 지출 %@"), won(s.total))) }
        if let p = store.vehicle.leaseProjection() { parts.append(String(format: L("적정 대비 %d%%"), p.paceRatioPct)) }
        if !store.records.isEmpty { parts.append(String(format: L("기록 %d건"), store.records.count)) }
        return parts.isEmpty ? L("기록을 추가하면 맞춤 브리핑을 보여드려요.") : parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                briefing
                spendCard
                ridingStatsCard
                maintenanceEntry
                leaseCard
                timeline
                aiInputBar
            }
            .padding(.bottom, 12)
        }
        .background(Theme.bgTop.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .sheet(isPresented: $showChecklist) { MaintenanceChecklistView(store: store) }
    }

    // 헤더
    private var header: some View {
        HStack {
            (Text("Wheelet") + Text(".").foregroundStyle(Theme.gold))
                .font(pd(20, .black))
                .kerning(1)
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(Theme.green).frame(width: 6, height: 6)
                Text("\(shortName) · \(store.vehicle.battery)% · \(store.vehicle.rangeKm)km")
                    .font(pd(11))
                    .foregroundStyle(Theme.silver)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.05))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // 정비 체크리스트 진입 (임박/초과 건수 요약)
    private var maintenanceEntry: some View {
        let checks = MaintenanceSchedule.checklist(vehicle: store.vehicle, records: store.records)
        let alert = checks.filter { $0.isOverdue || $0.isSoon }.count
        return Button { showChecklist = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "checklist").font(.system(size: 15)).foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 1) {
                    Text("정비 체크리스트").font(pd(13.5, .semibold))
                    Text(store.vehicle.vehicleCategory.label + " · " + String(format: L("점검 항목 %d개"), checks.count))
                        .font(pd(10.5)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if alert > 0 {
                    Text(String(format: L("%d건 임박"), alert))
                        .font(pd(10.5, .bold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.orange).clipShape(Capsule())
                }
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // 이번 달 주행/라이딩 통계 (drive 기록 집계)
    private var monthDrives: (km: Double, count: Int, min: Int) {
        let cal = Calendar.current
        let drives = store.records.filter {
            $0.kind == .drive && cal.isDate($0.occurredAt, equalTo: Date(), toGranularity: .month)
        }
        return (drives.compactMap { $0.distanceKm }.reduce(0, +),
                drives.count,
                drives.compactMap { $0.durationMin }.reduce(0, +))
    }

    @ViewBuilder
    private var ridingStatsCard: some View {
        let s = monthDrives
        if s.count > 0 {
            let isBike = store.vehicle.isBike
            VStack(alignment: .leading, spacing: 12) {
                Text(isBike ? "이번 달 라이딩" : "이번 달 주행").font(pd(13, .semibold)).foregroundStyle(Theme.silver)
                HStack(spacing: 0) {
                    statCell(L("거리"), "\(grouped(Int(s.km.rounded())))km")
                    cellDivider
                    statCell(isBike ? L("라이딩") : L("주행"), String(format: L("%d회"), s.count))
                    cellDivider
                    statCell(L("시간"), timeLabel(s.min))
                }
            }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.cardBorder, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(gm(18, .bold))
            Text(label).font(pd(10.5)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }
    private var cellDivider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 30)
    }
    private func timeLabel(_ minutes: Int) -> String {
        if minutes >= 60 { return String(format: L("%d시간 %d분"), minutes / 60, minutes % 60) }
        return String(format: L("%d분"), minutes)
    }

    // AI 브리핑
    private var briefing: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Theme.goldGradient)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                )
                .shadow(color: Theme.gold.opacity(0.3), radius: 7, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(briefingText)
                .font(pd(13))
                .lineSpacing(4)
                .foregroundStyle(Theme.textStrong)
                .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
                .background(Theme.cardAlt)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    chip("절약 플랜 보기", color: Theme.gold, border: Theme.gold.opacity(0.4))
                    chip("자세히 물어보기", color: Theme.silver, border: Color.white.opacity(0.12))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func chip(_ label: String, color: Color, border: Color) -> some View {
        Text(L(label))
            .font(pd(11))
            .foregroundStyle(color)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(border, lineWidth: 1))
    }

    // 월 지출
    private var spendCard: some View {
        let s = store.monthlySpend
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: String(format: L("%d월 총 지출"), s?.month ?? 7)).font(pd(11)).foregroundStyle(Theme.muted)
                    Text(won(s?.total ?? 186400)).font(gm(28, .bold))
                    spendDeltaText
                }
                Spacer()
                spendBars
            }
            HStack(spacing: 14) {
                if let s, !s.breakdown.isEmpty {
                    ForEach(s.breakdown, id: \.key) { item in
                        legend(spendColor(item.key), "\(item.label) \(won(item.amount))")
                    }
                } else {
                    legend(Theme.orange, "충전 ₩96,200")
                    legend(Theme.gold, "주유 ₩41,000")
                    legend(Theme.silver, "기타 ₩49,200")
                }
            }
            .padding(.top, 12)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.white.opacity(0.06)), alignment: .top)
            .padding(.top, 14)
        }
        .padding(EdgeInsets(top: 20, leading: 18, bottom: 20, trailing: 18))
        .background(
            LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 22)
    }

    @ViewBuilder
    private var spendDeltaText: some View {
        if let s = store.monthlySpend, s.prevTotal > 0 {
            if s.deltaWon <= 0 {
                Text(verbatim: String(format: L("지난달보다 %@ 아꼈어요"), won(-s.deltaWon))).font(pd(11)).foregroundStyle(Theme.green)
            } else {
                Text(verbatim: String(format: L("지난달보다 %@ 더 썼어요"), won(s.deltaWon))).font(pd(11)).foregroundStyle(Theme.orange)
            }
        } else if store.monthlySpend != nil {
            Text("이번 달 첫 지출 기록").font(pd(11)).foregroundStyle(Theme.muted)
        } else {
            Text("지난달보다 ₩25,300 아꼈어요").font(pd(11)).foregroundStyle(Theme.green)
        }
    }

    // 최근 5개월 막대 (마지막이 이번 달) — 데이터 없으면 데모 높이
    private var spendBars: some View {
        HStack(alignment: .bottom, spacing: 5) {
            bar(38, Color.white.opacity(0.1))
            bar(52, Color.white.opacity(0.1))
            bar(44, Color.white.opacity(0.1))
            bar(prevBarHeight, Color.white.opacity(0.14))
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Theme.goldLight, Theme.goldDark], startPoint: .top, endPoint: .bottom))
                .frame(width: 12, height: thisBarHeight)
        }
        .frame(height: 64, alignment: .bottom)
        .padding(.top, 6)
    }

    private var thisBarHeight: CGFloat {
        guard let s = store.monthlySpend, s.prevTotal > 0 || s.total > 0 else { return 40 }
        let maxV = max(s.total, s.prevTotal, 1)
        return max(10, CGFloat(s.total) / CGFloat(maxV) * 58)
    }
    private var prevBarHeight: CGFloat {
        guard let s = store.monthlySpend, s.prevTotal > 0 || s.total > 0 else { return 58 }
        let maxV = max(s.total, s.prevTotal, 1)
        return max(10, CGFloat(s.prevTotal) / CGFloat(maxV) * 58)
    }

    private func spendColor(_ key: String) -> Color {
        switch key {
        case "charge": return Theme.orange
        case "fuel": return Theme.gold
        case "maintenance": return Theme.green
        default: return Theme.silver
        }
    }

    private func bar(_ height: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 12, height: height)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).font(pd(11.5)).foregroundStyle(Theme.silver)
        }
    }

    // 렌트 약정거리
    private var leaseCard: some View {
        let p = store.vehicle.leaseProjection()
        let paceOver = (p?.paceRatioPct ?? 0) > 100
        let accent = paceOver ? Theme.orange : Theme.green
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("렌트 약정거리").font(pd(12, .semibold))
                Spacer()
                if let p {
                    Text("적정 대비 \(p.paceRatioPct)% · \(paceOver ? "과속" : "안전")")
                        .font(pd(11, .semibold))
                        .foregroundStyle(accent)
                } else {
                    Text(verbatim: String(format: L("잔여 %@km"), grouped(store.vehicle.leaseRemainKm)))
                        .font(pd(11)).foregroundStyle(Theme.orange)
                }
            }
            GeometryReader { geo in
                let allowRatio = p.map { min(1.0, Double($0.allowedToDateKm) / Double($0.limitKm)) } ?? 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color.white.opacity(0.18))
                        .frame(width: geo.size.width * CGFloat(allowRatio))
                    Capsule()
                        .fill(Theme.leaseGradient)
                        .frame(width: geo.size.width * CGFloat(store.vehicle.leasePct ?? 0) / 100)
                }
            }
            .frame(height: 6)
            .padding(.top, 10)
            HStack {
                if let p {
                    Text(verbatim: String(format: L("오늘 적정 %@km · 현재 %@km"), grouped(p.allowedToDateKm), grouped(store.vehicle.leaseDriven)))
                } else {
                    Text(verbatim: String(format: L("%@km 주행"), grouped(store.vehicle.leaseDriven)))
                }
                Spacer()
                Text(verbatim: String(format: L("약정 %@km"), grouped(store.vehicle.leaseLimitKm ?? 0)))
            }
            .font(pd(10))
            .foregroundStyle(Theme.muted)
            .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.25), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // 이번 주 기록 타임라인
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("이번 주 기록").font(pd(13, .semibold))
            VStack(spacing: 0) {
                ForEach(Array(store.records.enumerated()), id: \.element.id) { idx, rec in
                    timelineRow(rec, isLast: idx == store.records.count - 1)
                }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
    }

    private func dotColor(_ kind: RecordKind) -> Color {
        switch kind {
        case .charge: return Theme.orange
        case .fuel: return Theme.gold
        case .drive: return Theme.silver
        case .maintenance: return Theme.green
        }
    }

    private func timelineRow(_ rec: VaultRecord, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(dotColor(rec.kind)).frame(width: 8, height: 8).padding(.top, 5)
                if !isLast {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
                }
            }
            .frame(width: 20)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.title).font(pd(12.5, .medium))
                    timelineSubtitle(rec)
                }
                Spacer()
                trailing(rec)
            }
            .padding(.bottom, isLast ? 0 : 26)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func timelineSubtitle(_ rec: VaultRecord) -> some View {
        let t: Text
        switch rec.kind {
        case .maintenance:
            var s = Text(rec.location ?? "")
            if let tag = rec.tag { s = s + Text(" · \(tag)") }
            t = s
        default:
            var s = Text("\(relativeDay(rec.occurredAt)) \(timeOf(rec.occurredAt))")
            if rec.aiLogged {
                s = s + Text(" · AI 자동기록").foregroundStyle(Theme.gold)
            } else if let tag = rec.tag {
                s = s + Text(" · \(tag)")
            }
            t = s
        }
        return t.font(pd(10.5)).foregroundStyle(Theme.muted)
    }

    @ViewBuilder
    private func trailing(_ rec: VaultRecord) -> some View {
        switch rec.kind {
        case .charge, .fuel:
            if let amount = rec.amountWon {
                Text(won(amount)).font(gm(13))
            }
        case .drive:
            if let dur = rec.durationMin {
                Text(verbatim: String(format: L("%d분"), dur)).font(pd(11)).foregroundStyle(Theme.muted)
            }
        case .maintenance:
            if let amount = rec.amountWon {
                Text(won(amount)).font(gm(13))
            } else {
                Text("예약").font(pd(11)).foregroundStyle(Theme.gold)
            }
        }
    }

    // AI 입력 바
    private var aiInputBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.gold)
            Text("이번 달 충전비 얼마 썼어?")
                .font(pd(12.5))
                .foregroundStyle(Theme.muted)
            Spacer()
            Image(systemName: "arrow.up")
                .font(.system(size: 14))
                .foregroundStyle(Theme.silver)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.cardAlt)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.gold.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
