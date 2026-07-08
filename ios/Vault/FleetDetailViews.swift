import SwiftUI
import UIKit

/// Fleet 차량 상세 — 정보 + 이번 달 비용 + 기록 목록/추가.
struct FleetVehicleDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var fleet: FleetStore
    let vehicle: FleetVehicle
    @State private var showAddRecord = false
    @State private var showEdit = false

    private var records: [FleetRecord] {
        fleet.records.filter { $0.fleet_vehicle_id == vehicle.id }.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    HStack(spacing: 10) {
                        infoTile(L("누적 주행"), "\(grouped(vehicle.odometerKm))km")
                        infoTile(L("이번 달 비용"), won(fleet.monthlyCost(vehicleId: vehicle.id)))
                    }
                    HStack(spacing: 8) {
                        Button { showAddRecord = true } label: {
                            Label("기록 추가", systemImage: "plus").font(pd(13, .semibold)).foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity).padding(.vertical, 12).background(Theme.goldGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        if fleet.role == .manager {
                            Button { showEdit = true } label: {
                                Label("차량 수정", systemImage: "pencil").font(pd(13, .semibold)).foregroundStyle(Theme.gold)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold.opacity(0.4), lineWidth: 1))
                            }
                        }
                    }
                    Text("기록").font(pd(13, .semibold)).foregroundStyle(Theme.silver).padding(.top, 4)
                    if records.isEmpty {
                        Text("기록이 없어요").font(pd(12)).foregroundStyle(Theme.muted)
                    } else {
                        ForEach(records) { recordRow($0) }
                    }
                }
                .padding(16)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle(vehicle.plate ?? vehicle.name ?? "차량")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .tint(Theme.gold).preferredColorScheme(.dark)
        .sheet(isPresented: $showAddRecord) { FleetRecordAddView(fleet: fleet, vehicle: vehicle) }
        .sheet(isPresented: $showEdit) { FleetVehicleEditView(fleet: fleet, editing: vehicle) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12).fill(Theme.gold.opacity(0.14)).frame(width: 44, height: 44)
                .overlay(Image(systemName: vehicle.vehicleCategory.icon).font(.system(size: 18)).foregroundStyle(Theme.gold))
            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.model ?? vehicle.name ?? "-").font(pd(14, .semibold))
                if let d = vehicle.driverName, !d.isEmpty {
                    Label(d + (vehicle.driverPhone.map { " · \($0)" } ?? ""), systemImage: "person.fill")
                        .font(pd(11)).foregroundStyle(Theme.silver)
                }
            }
            Spacer()
        }
    }
    private func infoTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(pd(10)).foregroundStyle(Theme.muted)
            Text(value).font(gm(15, .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
    }
    private func recordRow(_ r: FleetRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(r.recordKind)).font(.system(size: 13)).foregroundStyle(Theme.gold).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title ?? r.recordKind.label).font(pd(12.5, .medium))
                Text(Self.df.string(from: r.date)).font(pd(10)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let a = r.amount_won { Text(won(a)).font(gm(12.5, .medium)) }
        }
        .padding(11).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
    }
    private func icon(_ k: RecordKind) -> String {
        switch k { case .charge: return "bolt.fill"; case .fuel: return "fuelpump.fill"; case .drive: return "clock"; case .maintenance: return "wrench.and.screwdriver.fill" }
    }
    private static let df: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "M/d HH:mm"; return f }()
}

/// Fleet 기록 추가
struct FleetRecordAddView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var fleet: FleetStore
    let vehicle: FleetVehicle
    @State private var kind: RecordKind = .fuel
    @State private var title = ""
    @State private var amount = ""
    @State private var odometer = ""
    @State private var memo = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("종류", selection: $kind) {
                    Text(L("주유")).tag(RecordKind.fuel)
                    Text(L("충전")).tag(RecordKind.charge)
                    Text(L("정비")).tag(RecordKind.maintenance)
                    Text(L("기타")).tag(RecordKind.drive)
                }.pickerStyle(.segmented)
                Section("내용") {
                    TextField("제목 (예: 경유 40L)", text: $title)
                    TextField("금액 (원)", text: $amount).keyboardType(.numberPad)
                    TextField("현재 주행 (km, 선택)", text: $odometer).keyboardType(.numberPad)
                    TextField("메모 (선택)", text: $memo)
                }
            }
            .navigationTitle("기록 추가").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        Task {
                            await fleet.addRecord(vehicleId: vehicle.id, kind: kind,
                                title: title.isEmpty ? kind.label : title,
                                amountWon: Int(amount), odometerKm: Int(odometer), memo: memo.isEmpty ? nil : memo)
                            dismiss()
                        }
                    }
                }
            }
        }
        .tint(Theme.gold).preferredColorScheme(.dark)
    }
}

/// Fleet 기사 드릴다운 — 담당 차량 + 이번 달 기록
struct FleetDriverDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var fleet: FleetStore
    let driverName: String
    @State private var detailVehicle: FleetVehicle?

    private var monthStart: Date { Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date() }
    private var vehicles: [FleetVehicle] {
        fleet.vehicles.filter { v in
            let dn = v.driverName ?? ""
            return dn.isEmpty ? driverName == L("담당 없음") : dn == driverName
        }
    }
    private var monthRecords: [FleetRecord] {
        let vids = Set(vehicles.map { $0.id })
        return fleet.records.filter { vids.contains($0.fleet_vehicle_id) && $0.date >= monthStart }.sorted { $0.date > $1.date }
    }
    private var stat: FleetStore.DriverStat? { fleet.driverStats().first { $0.name == driverName } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        tile(L("이번 달 비용"), won(stat?.cost ?? 0), Theme.gold)
                        tile(L("이번 달 주행"), "\(grouped(stat?.distanceKm ?? 0))km", Theme.silver)
                    }
                    Text("담당 차량").font(pd(13, .semibold)).foregroundStyle(Theme.silver).padding(.top, 2)
                    ForEach(vehicles) { v in
                        Button { detailVehicle = v } label: { vehicleRow(v) }.buttonStyle(.plain)
                    }
                    Text("이번 달 기록").font(pd(13, .semibold)).foregroundStyle(Theme.silver).padding(.top, 4)
                    if monthRecords.isEmpty {
                        Text("이번 달 기록이 없어요").font(pd(12)).foregroundStyle(Theme.muted)
                    } else {
                        ForEach(monthRecords) { recordRow($0) }
                    }
                }
                .padding(16)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle(driverName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .tint(Theme.gold).preferredColorScheme(.dark)
        .sheet(item: $detailVehicle) { FleetVehicleDetailView(fleet: fleet, vehicle: $0) }
    }

    private func tile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(pd(10)).foregroundStyle(Theme.muted)
            Text(value).font(gm(16, .bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
    }
    private func vehicleRow(_ v: FleetVehicle) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(Theme.gold.opacity(0.12)).frame(width: 34, height: 34)
                .overlay(Image(systemName: v.vehicleCategory.icon).font(.system(size: 14)).foregroundStyle(Theme.gold))
            VStack(alignment: .leading, spacing: 2) {
                Text(v.plate ?? v.name ?? "-").font(pd(13, .semibold))
                Text("\(grouped(v.odometerKm))km").font(pd(10)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(won(fleet.monthlyCost(vehicleId: v.id))).font(gm(12, .medium)).foregroundStyle(Theme.silver)
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(11).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
    }
    private func recordRow(_ r: FleetRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: rIcon(r.recordKind)).font(.system(size: 13)).foregroundStyle(Theme.gold).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title ?? r.recordKind.label).font(pd(12.5, .medium))
                Text(Self.df.string(from: r.date)).font(pd(10)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let a = r.amount_won { Text(won(a)).font(gm(12.5, .medium)) }
        }
        .padding(11).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
    }
    private func rIcon(_ k: RecordKind) -> String {
        switch k { case .charge: return "bolt.fill"; case .fuel: return "fuelpump.fill"; case .drive: return "clock"; case .maintenance: return "wrench.and.screwdriver.fill" }
    }
    private static let df: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "M/d HH:mm"; return f }()
}

/// Fleet 월간 리포트 + CSV(엑셀) 내보내기
struct FleetReportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var fleet: FleetStore
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let t = fleet.monthlyTotals()
                    Text("이번 달 합계").font(pd(13, .semibold)).foregroundStyle(Theme.silver)
                    HStack(spacing: 10) {
                        tile(L("주유·충전"), t.fuel, Theme.gold)
                        tile(L("정비"), t.maintenance, Theme.green)
                        tile(L("기타"), t.other, Theme.silver)
                    }
                    HStack {
                        Text(L("총 비용")).font(pd(13, .semibold))
                        Spacer()
                        Text(won(t.total)).font(gm(20, .bold)).foregroundStyle(Theme.gold)
                    }
                    .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))

                    if !driverRanks.isEmpty {
                        Text("기사별 이번 달 순위").font(pd(13, .semibold)).foregroundStyle(Theme.silver).padding(.top, 4)
                        ForEach(Array(driverRanks.enumerated()), id: \.element.id) { idx, s in
                            HStack(spacing: 8) {
                                Text("\(idx + 1)").font(gm(12, .bold))
                                    .foregroundStyle(idx == 0 ? Theme.gold : idx == 1 ? Theme.silver : idx == 2 ? Theme.orange : Theme.muted)
                                    .frame(width: 16)
                                Text(s.name).font(pd(12.5, .medium)).lineLimit(1)
                                Text(String(format: L("%d대"), s.vehicleCount)).font(pd(9.5)).foregroundStyle(Theme.muted2)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text(won(s.cost)).font(gm(12.5, .bold))
                                    Text("\(grouped(s.distanceKm))km").font(pd(9.5)).foregroundStyle(Theme.muted)
                                }
                            }
                            .padding(11).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                        }
                    }

                    Text("차량별 이번 달 비용").font(pd(13, .semibold)).foregroundStyle(Theme.silver).padding(.top, 4)
                    ForEach(fleet.vehicles) { v in
                        HStack {
                            Text(v.plate ?? v.name ?? "-").font(pd(12.5, .medium))
                            Spacer()
                            Text(won(fleet.monthlyCost(vehicleId: v.id))).font(gm(12.5, .medium)).foregroundStyle(Theme.silver)
                        }
                        .padding(11).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                    }
                }
                .padding(16)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("월간 리포트").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { shareURL = makePDF() } label: { Label("PDF 공유 (카톡·메일)", systemImage: "doc.richtext") }
                        Button { shareURL = makeCSV() } label: { Label("엑셀(CSV) 내보내기", systemImage: "tablecells") }
                    } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .tint(Theme.gold).preferredColorScheme(.dark)
        .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
    }

    // 기사별 순위 (비용 desc, 활동 있는 기사만)
    private var driverRanks: [FleetStore.DriverStat] {
        fleet.driverStats()
            .filter { $0.cost > 0 || $0.distanceKm > 0 }
            .sorted { ($0.cost, $0.distanceKm) > ($1.cost, $1.distanceKm) }
    }

    private func tile(_ label: String, _ amount: Int, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(won(amount)).font(gm(13, .bold)).foregroundStyle(color)
            Text(label).font(pd(10)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
    }

    /// 차량별 비용 + 기사별 순위 CSV 생성 → 임시 파일 URL
    private func makeCSV() -> URL? {
        func esc(_ cols: [String]) -> String {
            cols.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",") + "\n"
        }
        var csv = "차량번호,제조사,모델,담당기사,연락처,누적주행(km),이번달비용(원)\n"
        for v in fleet.vehicles {
            csv += esc([v.plate ?? "", v.maker ?? "", v.model ?? "", v.driverName ?? "", v.driverPhone ?? "",
                        "\(v.odometerKm)", "\(fleet.monthlyCost(vehicleId: v.id))"])
        }
        // 기사별 순위 표 (빈 줄로 구분)
        csv += "\n순위,기사,담당대수,이번달주행(km),이번달비용(원)\n"
        for (i, s) in driverRanks.enumerated() {
            csv += esc(["\(i + 1)", s.name, "\(s.vehicleCount)", "\(s.distanceKm)", "\(s.cost)"])
        }
        let name = (fleet.fleet?.name ?? "fleet") + "_report.csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let data = ("\u{FEFF}" + csv).data(using: .utf8) else { return nil }  // BOM: 엑셀 한글
        try? data.write(to: url)
        return url
    }

    /// 월간 리포트 PDF 생성 → 임시 파일 URL (카톡·메일 공유용)
    private func makePDF() -> URL? {
        let pageW: CGFloat = 595, pageH: CGFloat = 842, margin: CGFloat = 44
        let gold = UIColor(red: 0.83, green: 0.68, blue: 0.32, alpha: 1)
        let t = fleet.monthlyTotals()
        let month = Calendar.current.component(.month, from: Date())
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent((fleet.fleet?.name ?? "fleet") + "_리포트.pdf")
        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y: CGFloat = 52
                func draw(_ s: String, _ f: UIFont, _ c: UIColor = .black, _ dy: CGFloat = 24) {
                    (s as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: f, .foregroundColor: c]); y += dy
                }
                func rowLR(_ l: String, _ r: String, _ f: UIFont, _ c: UIColor = .black, _ dy: CGFloat = 20) {
                    (l as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: [.font: f, .foregroundColor: c])
                    let rw = (r as NSString).size(withAttributes: [.font: f]).width
                    (r as NSString).draw(at: CGPoint(x: pageW - margin - rw, y: y), withAttributes: [.font: f, .foregroundColor: c]); y += dy
                }
                func line() { let p = UIBezierPath(); p.move(to: CGPoint(x: margin, y: y)); p.addLine(to: CGPoint(x: pageW - margin, y: y)); UIColor(white: 0.85, alpha: 1).setStroke(); p.lineWidth = 0.5; p.stroke(); y += 14 }

                draw("\(fleet.fleet?.name ?? "Fleet") 월간 리포트", .boldSystemFont(ofSize: 22), gold, 28)
                draw(String(format: L("%d월 · 차량 %d대"), month, fleet.vehicles.count), .systemFont(ofSize: 13), .darkGray, 26)
                line()

                draw("이번 달 비용", .boldSystemFont(ofSize: 16), .black, 26)
                rowLR("총 비용", won(t.total), .boldSystemFont(ofSize: 15))
                rowLR("  · 주유·충전", won(t.fuel), .systemFont(ofSize: 12.5), .darkGray)
                rowLR("  · 정비", won(t.maintenance), .systemFont(ofSize: 12.5), .darkGray)
                rowLR("  · 기타", won(t.other), .systemFont(ofSize: 12.5), .darkGray)
                y += 10; line()

                if !driverRanks.isEmpty {
                    draw("기사별 순위 (비용)", .boldSystemFont(ofSize: 16), .black, 26)
                    for (i, s) in driverRanks.prefix(10).enumerated() where y < pageH - 120 {
                        rowLR("  \(i + 1). \(s.name) (\(s.vehicleCount)대)", "\(won(s.cost)) · \(grouped(s.distanceKm))km",
                              .systemFont(ofSize: 12), .darkGray)
                    }
                    y += 10; line()
                }

                draw("차량별 비용", .boldSystemFont(ofSize: 16), .black, 26)
                for v in fleet.vehicles where y < pageH - 70 {
                    rowLR("  " + (v.plate ?? v.name ?? "-"), won(fleet.monthlyCost(vehicleId: v.id)), .systemFont(ofSize: 12), .darkGray)
                }

                let df = DateFormatter(); df.locale = Locale(identifier: "ko_KR"); df.dateFormat = "yyyy.MM.dd HH:mm"
                ("생성: \(df.string(from: Date())) · Wheelet Fleet" as NSString).draw(at: CGPoint(x: margin, y: pageH - 44),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.lightGray])
            }
            return url
        } catch { return nil }
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// 공유 시트
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
