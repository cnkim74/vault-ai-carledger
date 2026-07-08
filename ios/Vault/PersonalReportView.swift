import SwiftUI
import UIKit

/// 개인용 월간 리포트 (프리미엄) — 이번 달 지출·주행·정비 요약 + PDF 생성/공유(카톡·메일).
struct PersonalReportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore
    @State private var shareURL: URL?

    private var v: Vehicle { store.vehicle }
    private var spend: MonthlySpend? { store.monthlySpend }
    private var month: Int { spend?.month ?? Calendar.current.component(.month, from: Date()) }
    private var upcoming: [MaintenanceDue] {
        MaintenanceSchedule.upcoming(vehicle: v, records: store.records).filter { $0.remainingKm <= 2000 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    spendSection
                    spendChartSection
                    vehicleSection
                    maintenanceSection
                    recordsSection
                    Button { shareURL = makePDF() } label: {
                        Label("PDF로 공유 (카톡·메일)", systemImage: "square.and.arrow.up")
                            .font(pd(14, .semibold)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.goldGradient).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("월간 리포트").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .tint(Theme.gold).preferredColorScheme(.dark)
        .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: String(format: L("%d월 리포트"), month)).font(gm(20, .bold)).foregroundStyle(Theme.gold)
            Text(v.name).font(pd(12)).foregroundStyle(Theme.muted)
        }
    }

    private var spendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("이번 달 지출").font(pd(13, .semibold)).foregroundStyle(Theme.silver)
            HStack {
                Text("총 지출").font(pd(13))
                Spacer()
                Text(won(spend?.total ?? 0)).font(gm(20, .bold)).foregroundStyle(Theme.gold)
            }
            if let s = spend {
                ForEach(s.breakdown, id: \.key) { b in
                    HStack {
                        Text(L(b.label)).font(pd(11.5)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text(won(b.amount)).font(gm(12.5, .medium)).foregroundStyle(Theme.silver)
                    }
                }
                if let pct = s.deltaPct {
                    Text(verbatim: String(format: L("지난달 대비 %@%d%%"), pct <= 0 ? "−" : "+", abs(pct)))
                        .font(pd(11)).foregroundStyle(pct <= 0 ? Theme.green : Theme.orange)
                }
            }
        }
        .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
    }

    // 지출 구성 막대 차트
    private var recentRecords: [VaultRecord] {
        store.records.sorted { $0.occurredAt > $1.occurredAt }
    }
    private func spendColor(_ key: String) -> Color {
        switch key { case "charge": return Theme.orange; case "fuel": return Theme.gold
        case "maintenance": return Theme.green; default: return Theme.silver }
    }
    @ViewBuilder
    private var spendChartSection: some View {
        if let s = spend, !s.breakdown.isEmpty {
            let maxAmt = max(1, s.breakdown.map { $0.amount }.max() ?? 1)
            VStack(alignment: .leading, spacing: 10) {
                Text("지출 구성").font(pd(13, .semibold)).foregroundStyle(Theme.silver)
                ForEach(s.breakdown, id: \.key) { b in
                    VStack(spacing: 4) {
                        HStack {
                            Text(L(b.label)).font(pd(11)).foregroundStyle(Theme.muted)
                            Spacer()
                            Text(won(b.amount)).font(gm(11.5, .medium)).foregroundStyle(Theme.text)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.cardBorder).frame(height: 6)
                                Capsule().fill(spendColor(b.key))
                                    .frame(width: max(6, geo.size.width * CGFloat(b.amount) / CGFloat(maxAmt)), height: 6)
                            }
                        }.frame(height: 6)
                    }
                }
            }
            .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
        }
    }

    // 최근 기록 목록
    @ViewBuilder
    private var recordsSection: some View {
        if !recentRecords.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("최근 기록").font(pd(13, .semibold)).foregroundStyle(Theme.silver)
                ForEach(recentRecords.prefix(8)) { r in
                    HStack(spacing: 10) {
                        Image(systemName: recIcon(r.kind)).font(.system(size: 12)).foregroundStyle(Theme.gold).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.title).font(pd(12, .medium)).lineLimit(1)
                            Text(Self.df.string(from: r.occurredAt)).font(pd(9.5)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if let a = r.amountWon { Text(won(a)).font(gm(12, .medium)) }
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
        }
    }
    private func recIcon(_ k: RecordKind) -> String {
        switch k { case .charge: return "bolt.fill"; case .fuel: return "fuelpump.fill"; case .drive: return "clock"; case .maintenance: return "wrench.and.screwdriver.fill" }
    }
    private static let df: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "M/d HH:mm"; return f }()

    private var vehicleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("차량").font(pd(13, .semibold)).foregroundStyle(Theme.silver)
            reportRow(L("누적 주행"), "\(grouped(v.odometerKm))km")
            if let limit = v.leaseLimitKm, limit > 0 {
                reportRow(L("약정거리"), "\(grouped(v.leaseDriven)) / \(grouped(limit))km (\(v.leasePct ?? 0)%)")
            }
        }
        .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("정비 예정").font(pd(13, .semibold)).foregroundStyle(Theme.silver)
            if upcoming.isEmpty {
                Text("임박한 정비 항목이 없어요").font(pd(12)).foregroundStyle(Theme.muted)
            } else {
                ForEach(upcoming) { d in
                    reportRow(L(d.item), d.isOverdue ? String(format: L("%dkm 초과"), -d.remainingKm)
                                                     : String(format: L("%dkm 남음"), d.remainingKm),
                              color: d.isOverdue ? Theme.red : Theme.orange)
                }
            }
        }
        .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private func reportRow(_ label: String, _ value: String, color: Color = Theme.text) -> some View {
        HStack {
            Text(label).font(pd(12)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(gm(12.5, .medium)).foregroundStyle(color)
        }
    }

    private func pdfColor(_ key: String) -> UIColor {
        switch key {
        case "charge": return .systemOrange
        case "fuel": return UIColor(red: 0.83, green: 0.68, blue: 0.32, alpha: 1)
        case "maintenance": return .systemGreen
        default: return .systemGray
        }
    }

    // MARK: PDF 생성
    private func makePDF() -> URL? {
        let pageW: CGFloat = 595, pageH: CGFloat = 842, margin: CGFloat = 44
        let gold = UIColor(red: 0.83, green: 0.68, blue: 0.32, alpha: 1)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Wheelet_월간리포트.pdf")
        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y: CGFloat = 52
                func draw(_ s: String, _ font: UIFont, _ color: UIColor = .black, _ dy: CGFloat = 24, indent: CGFloat = 0) {
                    (s as NSString).draw(at: CGPoint(x: margin + indent, y: y), withAttributes: [.font: font, .foregroundColor: color])
                    y += dy
                }
                func rowLR(_ left: String, _ right: String, _ font: UIFont, _ color: UIColor = .black, _ dy: CGFloat = 20) {
                    (left as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: font, .foregroundColor: color])
                    let rw = (right as NSString).size(withAttributes: [.font: font]).width
                    (right as NSString).draw(at: CGPoint(x: pageW - margin - rw, y: y), withAttributes: [.font: font, .foregroundColor: color])
                    y += dy
                }
                func line() { let p = UIBezierPath(); p.move(to: CGPoint(x: margin, y: y)); p.addLine(to: CGPoint(x: pageW - margin, y: y)); UIColor(white: 0.85, alpha: 1).setStroke(); p.lineWidth = 0.5; p.stroke(); y += 14 }

                draw("Wheelet 월간 리포트", .boldSystemFont(ofSize: 24), gold, 30)
                draw(String(format: L("%d월 · %@"), month, v.name), .systemFont(ofSize: 13), .darkGray, 26)
                line()

                draw("이번 달 지출", .boldSystemFont(ofSize: 16), .black, 26)
                rowLR("총 지출", won(spend?.total ?? 0), .boldSystemFont(ofSize: 15))
                if let s = spend {
                    if let pct = s.deltaPct {
                        rowLR("지난달 대비", (pct <= 0 ? "−" : "+") + "\(abs(pct))%", .systemFont(ofSize: 12.5),
                              pct <= 0 ? UIColor.systemGreen : UIColor.systemOrange)
                    }
                    // 지출 구성 막대
                    let maxAmt = max(1, s.breakdown.map { $0.amount }.max() ?? 1)
                    let barMaxW = pageW - margin * 2 - 150
                    for b in s.breakdown {
                        let rowY = y
                        (("  " + L(b.label)) as NSString).draw(at: CGPoint(x: margin, y: rowY),
                            withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.darkGray])
                        let bw = barMaxW * CGFloat(b.amount) / CGFloat(maxAmt)
                        let barColor = pdfColor(b.key)
                        let bar = UIBezierPath(roundedRect: CGRect(x: margin + 90, y: rowY + 2, width: max(3, bw), height: 8), cornerRadius: 4)
                        barColor.setFill(); bar.fill()
                        let amt = won(b.amount) as NSString
                        let aw = amt.size(withAttributes: [.font: UIFont.systemFont(ofSize: 11)]).width
                        amt.draw(at: CGPoint(x: pageW - margin - aw, y: rowY),
                                 withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.gray])
                        y += 18
                    }
                }
                y += 10; line()

                draw("차량", .boldSystemFont(ofSize: 16), .black, 26)
                rowLR("누적 주행", "\(grouped(v.odometerKm)) km", .systemFont(ofSize: 12.5), .darkGray)
                if let limit = v.leaseLimitKm, limit > 0 {
                    rowLR("약정거리", "\(grouped(v.leaseDriven)) / \(grouped(limit)) km (\(v.leasePct ?? 0)%)", .systemFont(ofSize: 12.5), .darkGray)
                }
                y += 10; line()

                draw("정비 예정", .boldSystemFont(ofSize: 16), .black, 26)
                if upcoming.isEmpty {
                    draw("임박한 정비 항목이 없어요", .systemFont(ofSize: 12.5), .gray, 20)
                } else {
                    for d in upcoming {
                        rowLR("  · " + L(d.item),
                              d.isOverdue ? "\(-d.remainingKm)km 초과" : "\(d.remainingKm)km 남음",
                              .systemFont(ofSize: 12.5), d.isOverdue ? UIColor.systemRed : UIColor.systemOrange)
                    }
                }

                // 최근 기록 (지면 남는 만큼)
                if !recentRecords.isEmpty {
                    y += 10; line()
                    draw("최근 기록", .boldSystemFont(ofSize: 16), .black, 26)
                    let rdf = DateFormatter(); rdf.locale = Locale(identifier: "ko_KR"); rdf.dateFormat = "M/d"
                    for r in recentRecords.prefix(12) where y < pageH - 80 {
                        let left = "  \(rdf.string(from: r.occurredAt))  \(r.title)"
                        rowLR(left, r.amountWon.map { won($0) } ?? "-", .systemFont(ofSize: 12), .darkGray)
                    }
                }

                let df = DateFormatter(); df.locale = Locale(identifier: "ko_KR"); df.dateFormat = "yyyy.MM.dd HH:mm"
                let footer = "생성: \(df.string(from: Date())) · Wheelet"
                (footer as NSString).draw(at: CGPoint(x: margin, y: pageH - 44),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.lightGray])
            }
            return url
        } catch { return nil }
    }
}
