import SwiftUI
import UniformTypeIdentifiers

/// 기업용 Fleet — 관리자 대시보드(한눈에 보기) + CSV 대량등록 + 차량/기사 관리. (유료)
struct FleetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var premium: PremiumStore
    @StateObject private var fleet = FleetStore()
    @StateObject private var auth = AuthService()
    @State private var newFleetName = ""
    @State private var showAddVehicle = false
    @State private var editingVehicle: FleetVehicle?
    @State private var detailVehicle: FleetVehicle?
    @State private var showReport = false
    @State private var showImporter = false
    @State private var importMsg: String?
    @State private var showPaywall = false
    @State private var groupByDriver = false
    @State private var joinCode = ""
    @State private var joinError: String?
    @State private var quickRecordVehicle: FleetVehicle?
    @State private var showChooseVehicle = false
    @State private var vehicleFilter: DashFilter = .all

    enum DashFilter { case all, due, over }

    var body: some View {
        NavigationStack {
            Group {
                if !premium.isPremium {
                    lockedState
                } else if !auth.isAuthenticated {
                    AuthView(auth: auth)
                } else {
                    switch fleet.role {
                    case .manager: dashboard
                    case .driver: driverDashboard
                    case .none: createOrJoinState
                    }
                }
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("기업용 Fleet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                if premium.isPremium && auth.isAuthenticated {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if fleet.role == .manager {
                            Button { showReport = true } label: { Image(systemName: "chart.bar.doc.horizontal") }
                        }
                        Menu {
                            if fleet.role == .manager {
                                Button { showAddVehicle = true } label: { Label("차량 추가", systemImage: "plus") }
                                Button { showImporter = true } label: { Label("CSV 대량등록", systemImage: "square.and.arrow.down") }
                                Divider()
                            }
                            Button(role: .destructive) { auth.signOut(); fleet.role = .none; fleet.fleets = []; fleet.vehicles = [] } label: { Label("로그아웃", systemImage: "arrow.right.square") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .task {
            fleet.auth = auth
            if premium.isPremium && auth.isAuthenticated { await fleet.load(uid: auth.userID) }
        }
        .onChange(of: auth.isAuthenticated) { _, signedIn in
            fleet.auth = auth
            if signedIn { Task { await fleet.load(uid: auth.userID) } }
        }
        .sheet(isPresented: $showAddVehicle) { FleetVehicleEditView(fleet: fleet, editing: nil) }
        .sheet(item: $editingVehicle) { FleetVehicleEditView(fleet: fleet, editing: $0) }
        .sheet(item: $detailVehicle) { FleetVehicleDetailView(fleet: fleet, vehicle: $0) }
        .sheet(item: $quickRecordVehicle) { FleetRecordAddView(fleet: fleet, vehicle: $0) }
        .sheet(isPresented: $showReport) { FleetReportView(fleet: fleet) }
        .confirmationDialog("어느 차량 기록을 추가할까요?", isPresented: $showChooseVehicle, titleVisibility: .visible) {
            ForEach(fleet.vehicles) { v in
                Button(v.plate ?? v.model ?? v.name ?? "-") { quickRecordVehicle = v }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallSheet(premium: premium) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .text], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    // 유료 안내
    private var lockedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2.crop.circle.fill").font(.system(size: 44)).foregroundStyle(Theme.gold).padding(.top, 30)
            Text("기업용 Fleet").font(gm(20, .bold))
            Text("택시·운송·렌터카 등 다수 차량을 대량 등록하고, 관리자가 한눈에 관리하는 유료 기능이에요.")
                .font(pd(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 24)
            VStack(alignment: .leading, spacing: 10) {
                perk("square.and.arrow.down", "CSV로 차량 대량 등록")
                perk("rectangle.grid.2x2.fill", "관리자 대시보드 · 한눈에 보기")
                perk("person.2.fill", "차량별 담당 기사 지정")
            }
            .padding(16).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
            .padding(.horizontal, 20)
            Spacer()
            Button { showPaywall = true } label: {
                Text("Fleet 시작하기").font(pd(15, .semibold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 15).background(Theme.goldGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }.padding(20)
        }
    }
    private func perk(_ icon: String, _ t: String) -> some View {
        HStack(spacing: 12) { Image(systemName: icon).foregroundStyle(Theme.gold).frame(width: 24); Text(t).font(pd(13)); Spacer() }
    }

    // 신규 사용자: 관리자로 조직 생성 OR 기사로 코드 참여
    private var createOrJoinState: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "building.2.fill").font(.system(size: 38)).foregroundStyle(Theme.gold).padding(.top, 30)

                VStack(alignment: .leading, spacing: 10) {
                    Label("관리자로 시작", systemImage: "person.badge.key.fill").font(pd(13, .semibold)).foregroundStyle(Theme.silver)
                    TextField("회사/조직 이름 (예: OO운수)", text: $newFleetName)
                        .font(pd(14)).padding(13).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                    Button {
                        let n = newFleetName.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty { Task { await fleet.createFleet(name: n); newFleetName = ""; await fleet.load(uid: auth.userID) } }
                    } label: {
                        Text("조직 만들기").font(pd(14, .semibold)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 13).background(Theme.goldGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }.disabled(newFleetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16).background(Theme.card.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1)).padding(.horizontal, 20)

                Text("또는").font(pd(11)).foregroundStyle(Theme.muted)

                VStack(alignment: .leading, spacing: 10) {
                    Label("기사로 참여", systemImage: "person.fill").font(pd(13, .semibold)).foregroundStyle(Theme.silver)
                    TextField("참여 코드 (관리자에게 받으세요)", text: $joinCode)
                        .font(pd(14)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .padding(13).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                    if let e = joinError { Text(e).font(pd(11)).foregroundStyle(.red) }
                    Button {
                        let c = joinCode.trimmingCharacters(in: .whitespaces)
                        if !c.isEmpty { Task {
                            let r = await fleet.joinByCode(c)
                            if r.ok { joinCode = ""; joinError = nil; await fleet.load(uid: auth.userID) }
                            else { joinError = r.error }
                        } }
                    } label: {
                        Text("참여하기").font(pd(14, .semibold)).foregroundStyle(Theme.gold)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
                    }.disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16).background(Theme.card.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1)).padding(.horizontal, 20)
            }
        }
    }

    // 기사 대시보드: 배정된 차량만 + 빠른 기록
    private var driverDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(fleet.fleet?.name ?? "").font(gm(17, .bold))
                    Spacer()
                    Text("기사").font(pd(10.5, .bold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.silver).clipShape(Capsule())
                }.padding(.horizontal, 4)
                if fleet.vehicles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "car.fill").font(.system(size: 28)).foregroundStyle(Theme.muted)
                        Text("배정된 차량이 없어요").font(pd(13)).foregroundStyle(Theme.muted)
                        Text("관리자가 차량을 배정하면 여기에 표시돼요").font(pd(10.5)).foregroundStyle(Theme.muted2)
                    }.frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    // 내 요약: 배정 대수 · 이번 달 내 비용
                    HStack(spacing: 10) {
                        summaryCell(L("내 차량"), fleet.vehicles.count, Theme.silver)
                        valueCell(L("이번 달 비용"), won(driverMonthCost), Theme.gold)
                    }
                    // 정비 임박/초과 경고
                    if let w = serviceWarning(fleet.vehicles) { warnBanner(w.text, w.color) }
                    // 빠른 기록 추가
                    Button {
                        if fleet.vehicles.count == 1 { quickRecordVehicle = fleet.vehicles[0] }
                        else { showChooseVehicle = true }
                    } label: {
                        Label("주유·주행 기록 추가", systemImage: "plus.circle.fill")
                            .font(pd(14, .semibold)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Theme.goldGradient).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text("내 차량").font(pd(12, .semibold)).foregroundStyle(Theme.silver).padding(.top, 4)
                    ForEach(fleet.vehicles) { v in
                        Button { detailVehicle = v } label: { vehicleRow(v) }.buttonStyle(.plain)
                    }
                }
            }.padding(16)
        }
    }
    // 기사: 이번 달 배정 차량 비용 합
    private var driverMonthCost: Int { fleet.vehicles.map { fleet.monthlyCost(vehicleId: $0.id) }.reduce(0, +) }

    // 대시보드
    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 조직 + 요약
                HStack {
                    if fleet.fleets.count > 1 {
                        Menu {
                            ForEach(fleet.fleets) { f in Button(f.name) { Task { await fleet.selectFleet(f.id) } } }
                        } label: {
                            HStack(spacing: 5) { Text(fleet.fleet?.name ?? "").font(gm(17, .bold)); Image(systemName: "chevron.down").font(.system(size: 11)) }
                                .foregroundStyle(Theme.text)
                        }
                    } else {
                        Text(fleet.fleet?.name ?? "").font(gm(17, .bold))
                    }
                    Spacer()
                    Text(String(format: L("총 %d대"), fleet.vehicles.count)).font(pd(12, .semibold)).foregroundStyle(Theme.gold)
                }
                .padding(.horizontal, 4)

                // 참여 코드 (기사에게 공유) + 기사 수
                if let code = fleet.fleet?.join_code {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus").font(.system(size: 12)).foregroundStyle(Theme.gold)
                        Text("참여 코드").font(pd(11)).foregroundStyle(Theme.muted)
                        Text(code).font(gm(13, .bold)).foregroundStyle(Theme.gold).textSelection(.enabled)
                        Spacer()
                        Text(String(format: L("기사 %d명"), fleet.members.count)).font(pd(11)).foregroundStyle(Theme.silver)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold.opacity(0.25), lineWidth: 1))
                }

                if fleet.vehicles.isEmpty {
                    emptyVehicles
                } else {
                    summaryBar
                    costCard
                    if let w = serviceWarning(fleet.vehicles), vehicleFilter == .all { warnBanner(w.text, w.color) }
                    // 보기 전환
                    Picker("", selection: $groupByDriver) {
                        Text("전체").tag(false)
                        Text("기사별").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 2)

                    if groupByDriver {
                        ForEach(driverGroups, id: \.0) { name, vs in
                            HStack(spacing: 6) {
                                Image(systemName: "person.fill").font(.system(size: 11)).foregroundStyle(Theme.silver)
                                Text(name).font(pd(12, .semibold)).foregroundStyle(Theme.silver)
                                Text("\(vs.count)").font(pd(11)).foregroundStyle(Theme.muted)
                            }
                            .padding(.top, 6)
                            ForEach(vs) { v in
                                Button { detailVehicle = v } label: { vehicleRow(v) }.buttonStyle(.plain)
                            }
                        }
                    } else {
                        if filteredVehicles.isEmpty {
                            Text("해당하는 차량이 없어요").font(pd(12)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 20)
                        }
                        ForEach(filteredVehicles) { v in
                            Button { detailVehicle = v } label: { vehicleRow(v) }.buttonStyle(.plain)
                        }
                    }

                    driverSection
                }
                if let msg = importMsg {
                    Text(msg).font(pd(11)).foregroundStyle(Theme.green).padding(.top, 4)
                }
            }
            .padding(16)
        }
    }

    // 요약: 전체 · 정비 임박 · 초과 (탭하면 목록 필터)
    private var summaryBar: some View {
        HStack(spacing: 10) {
            filterCell(L("전체"), fleet.vehicles.count, Theme.silver, .all)
            filterCell(L("정비 임박"), dueCount, Theme.orange, .due)
            filterCell(L("정비 초과"), overCount, Theme.red, .over)
        }
    }
    private var dueCount: Int { fleet.vehicles.filter { if let r = $0.serviceRemaining { return r >= 0 && r <= 2000 }; return false }.count }
    private var overCount: Int { fleet.vehicles.filter { ($0.serviceRemaining ?? 1) < 0 }.count }

    private func filterCell(_ label: String, _ n: Int, _ color: Color, _ f: DashFilter) -> some View {
        let on = vehicleFilter == f
        return Button { vehicleFilter = (on && f != .all) ? .all : f } label: {
            VStack(spacing: 3) {
                Text("\(n)").font(gm(19, .bold)).foregroundStyle(n > 0 ? color : Theme.text)
                Text(label).font(pd(10)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(on ? color.opacity(0.14) : Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? color.opacity(0.6) : Theme.cardBorder, lineWidth: 1))
        }.buttonStyle(.plain)
    }
    private func summaryCell(_ label: String, _ n: Int, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(n)").font(gm(19, .bold)).foregroundStyle(n > 0 ? color : Theme.text)
            Text(label).font(pd(10)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
    }
    // 금액용 타일
    private func valueCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(gm(16, .bold)).foregroundStyle(color)
            Text(label).font(pd(10)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
    }
    // 정비 임박/초과 경고 배너
    private func serviceWarning(_ vs: [FleetVehicle]) -> (text: String, color: Color)? {
        let over = vs.filter { ($0.serviceRemaining ?? 1) < 0 }.count
        let due = vs.filter { if let r = $0.serviceRemaining { return r >= 0 && r <= 2000 }; return false }.count
        if over > 0 { return (String(format: L("정비 시기를 지난 차량 %d대가 있어요"), over), Theme.red) }
        if due > 0 { return (String(format: L("정비 시기가 임박한 차량 %d대"), due), Theme.orange) }
        return nil
    }
    private func warnBanner(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 12)).foregroundStyle(color)
            Text(text).font(pd(11.5, .semibold)).foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(color.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.35), lineWidth: 1))
    }
    // 현재 필터가 적용된 차량 목록
    private var filteredVehicles: [FleetVehicle] {
        switch vehicleFilter {
        case .all: return fleet.vehicles
        case .due: return fleet.vehicles.filter { if let r = $0.serviceRemaining { return r >= 0 && r <= 2000 }; return false }
        case .over: return fleet.vehicles.filter { ($0.serviceRemaining ?? 1) < 0 }
        }
    }
    // 기사별 그룹 (담당 없음은 마지막)
    private var driverGroups: [(String, [FleetVehicle])] {
        let grouped = Dictionary(grouping: filteredVehicles) { $0.driverName?.isEmpty == false ? $0.driverName! : L("담당 없음") }
        return grouped.sorted { a, b in
            if a.key == L("담당 없음") { return false }; if b.key == L("담당 없음") { return true }
            return a.key < b.key
        }
    }

    // 이번 달 비용 카드 (탭 → 월간 리포트)
    private var costCard: some View {
        let t = fleet.monthlyTotals()
        return Button { showReport = true } label: {
            VStack(spacing: 8) {
                HStack {
                    Label("이번 달 비용", systemImage: "wonsign.circle.fill").font(pd(12, .semibold)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(won(t.total)).font(gm(18, .bold)).foregroundStyle(Theme.gold)
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                HStack(spacing: 14) {
                    costLegend(L("주유·충전"), won(t.fuel), Theme.gold)
                    costLegend(L("정비"), won(t.maintenance), Theme.green)
                    costLegend(L("기타"), won(t.other), Theme.silver)
                    Spacer()
                }
            }
            .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
        }.buttonStyle(.plain)
    }
    private func costLegend(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(pd(9)).foregroundStyle(Theme.muted)
                Text(value).font(pd(10.5, .semibold))
            }
        }
    }

    // 기사 관리 — 참여한 기사 목록 + 담당 대수
    private var driverSection: some View {
        Group {
            if !fleet.members.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill").font(.system(size: 12)).foregroundStyle(Theme.silver)
                        Text("기사 관리").font(pd(12, .semibold)).foregroundStyle(Theme.silver)
                        Text("\(fleet.members.count)").font(pd(11)).foregroundStyle(Theme.muted)
                    }
                    ForEach(fleet.members) { m in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 9).fill(Theme.silver.opacity(0.12)).frame(width: 32, height: 32)
                                .overlay(Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(Theme.silver))
                            Text(m.email ?? m.user_id.prefix(8).description).font(pd(12.5)).lineLimit(1)
                            Spacer()
                            let n = fleet.vehicles.filter { $0.assignedUserId == m.user_id }.count
                            Text(n > 0 ? String(format: L("담당 %d대"), n) : L("미배정"))
                                .font(pd(10.5, .semibold)).foregroundStyle(n > 0 ? Theme.gold : Theme.muted)
                        }
                        .padding(11).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var emptyVehicles: some View {
        VStack(spacing: 10) {
            Image(systemName: "car.2.fill").font(.system(size: 30)).foregroundStyle(Theme.muted)
            Text("등록된 차량이 없어요").font(pd(13)).foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                Button { showAddVehicle = true } label: {
                    Label("차량 추가", systemImage: "plus").font(pd(12, .semibold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 9).background(Theme.goldGradient).clipShape(Capsule())
                }
                Button { showImporter = true } label: {
                    Label("CSV 대량등록", systemImage: "square.and.arrow.down").font(pd(12, .semibold)).foregroundStyle(Theme.gold)
                        .padding(.horizontal, 14).padding(.vertical, 9).overlay(Capsule().stroke(Theme.gold.opacity(0.5), lineWidth: 1))
                }
            }
            Text("CSV 형식: 차량번호,모델,연식,연료,차종,누적주행,기사,연락처").font(pd(9.5)).foregroundStyle(Theme.muted2).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }

    private func vehicleRow(_ v: FleetVehicle) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(Theme.gold.opacity(0.12)).frame(width: 38, height: 38)
                .overlay(Image(systemName: v.vehicleCategory.icon).font(.system(size: 15)).foregroundStyle(Theme.gold))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(v.plate ?? v.name ?? "-").font(pd(13.5, .semibold))
                    if let m = v.model { Text(m).font(pd(10.5)).foregroundStyle(Theme.muted).lineLimit(1) }
                }
                HStack(spacing: 6) {
                    if let d = v.driverName, !d.isEmpty {
                        Label(d, systemImage: "person.fill").font(pd(10)).foregroundStyle(Theme.silver)
                    }
                    Text("\(grouped(v.odometerKm))km").font(pd(10)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            if let r = v.serviceRemaining {
                Text(r < 0 ? String(format: L("%dkm 초과"), -r) : String(format: L("%dkm 남음"), r))
                    .font(pd(10, .semibold))
                    .foregroundStyle(r < 0 ? Theme.red : (r <= 2000 ? Theme.orange : Theme.green))
            }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(12).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let text = String(data: data, encoding: .utf8) ?? decodeEUCKR(data) ?? ""
        let rows = FleetCSV.parse(text)
        guard !rows.isEmpty else { importMsg = L("불러올 차량이 없어요. CSV 형식을 확인하세요."); return }
        Task {
            let n = await fleet.bulkInsert(rows)
            importMsg = String(format: L("%d대 대량 등록됨"), n)
        }
    }
    private func decodeEUCKR(_ data: Data) -> String? {
        let enc = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: enc))
    }
}

/// Fleet 차량 추가/수정
struct FleetVehicleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var fleet: FleetStore
    let editing: FleetVehicle?

    @State private var plate: String
    @State private var model: String
    @State private var year: String
    @State private var category: VehicleCategory
    @State private var fuel: String
    @State private var odometer: String
    @State private var driverName: String
    @State private var driverPhone: String
    @State private var memo: String
    @State private var nextService: String
    @State private var assignedUserId: String?
    @State private var showDelete = false

    init(fleet: FleetStore, editing: FleetVehicle?) {
        self.fleet = fleet; self.editing = editing
        _assignedUserId = State(initialValue: editing?.assignedUserId)
        _plate = State(initialValue: editing?.plate ?? "")
        _model = State(initialValue: editing?.model ?? "")
        _year = State(initialValue: editing?.year.map(String.init) ?? "")
        _category = State(initialValue: editing?.vehicleCategory ?? .car)
        _fuel = State(initialValue: editing?.fuel ?? FuelType.gasoline.rawValue)
        _odometer = State(initialValue: String(editing?.odometerKm ?? 0))
        _driverName = State(initialValue: editing?.driverName ?? "")
        _driverPhone = State(initialValue: editing?.driverPhone ?? "")
        _memo = State(initialValue: editing?.memo ?? "")
        _nextService = State(initialValue: editing?.nextServiceKm.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("차량") {
                    TextField("차량 번호 (예: 62가 3817)", text: $plate)
                    Picker("차종", selection: $category) {
                        ForEach(VehicleCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    TextField("모델", text: $model)
                    TextField("연식 (예: 2024)", text: $year).keyboardType(.numberPad)
                    Picker("연료", selection: $fuel) {
                        ForEach(FuelType.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    TextField("누적 주행 (km)", text: $odometer).keyboardType(.numberPad)
                    TextField("다음 정비 (km, 선택)", text: $nextService).keyboardType(.numberPad)
                }
                Section("담당 기사") {
                    TextField("기사 이름", text: $driverName)
                    TextField("연락처", text: $driverPhone).keyboardType(.phonePad)
                    TextField("메모 (선택)", text: $memo)
                    if !fleet.members.isEmpty {
                        Picker("기사 계정 배정", selection: $assignedUserId) {
                            Text("미배정").tag(String?.none)
                            ForEach(fleet.members) { m in
                                Text(m.email ?? m.user_id.prefix(8).description).tag(String?.some(m.user_id))
                            }
                        }
                    }
                }
                if editing != nil {
                    Section { Button(role: .destructive) { showDelete = true } label: { HStack { Spacer(); Text("차량 삭제"); Spacer() } } }
                }
            }
            .navigationTitle(editing == nil ? "차량 추가" : "차량 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("저장") { Task { await save() } }.disabled(plate.isEmpty && model.isEmpty) }
            }
        }
        .tint(Theme.gold).preferredColorScheme(.dark)
        .confirmationDialog("이 차량을 삭제할까요?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("차량 삭제", role: .destructive) { Task { if let e = editing { await fleet.deleteVehicle(id: e.id) }; dismiss() } }
            Button("취소", role: .cancel) {}
        }
    }

    private func save() async {
        let up = FleetStore.VehicleUpsert(
            plate: plate.isEmpty ? nil : plate, name: plate.isEmpty ? model : plate,
            model: model.isEmpty ? nil : model, year: Int(year), category: category.rawValue,
            fuel: fuel, odometer_km: Int(odometer) ?? 0,
            driver_name: driverName.isEmpty ? nil : driverName,
            driver_phone: driverPhone.isEmpty ? nil : driverPhone,
            memo: memo.isEmpty ? nil : memo, status: "active",
            next_service_km: Int(nextService), assigned_user_id: assignedUserId)
        if let e = editing {
            await fleet.updateVehicle(id: e.id, up)
            await fleet.assignDriver(vehicleId: e.id, userId: assignedUserId) // 배정/해제(null) 명시 반영
        } else { await fleet.addVehicle(up) }
        dismiss()
    }
}
