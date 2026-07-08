import SwiftUI
import UniformTypeIdentifiers

/// 기업용 Fleet — 관리자 대시보드(한눈에 보기) + CSV 대량등록 + 차량/기사 관리. (유료)
struct FleetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var premium: PremiumStore
    @StateObject private var fleet = FleetStore()
    @State private var newFleetName = ""
    @State private var showAddVehicle = false
    @State private var editingVehicle: FleetVehicle?
    @State private var showImporter = false
    @State private var importMsg: String?
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if !premium.isPremium {
                    lockedState
                } else if fleet.fleets.isEmpty {
                    createFleetState
                } else {
                    dashboard
                }
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("기업용 Fleet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                if premium.isPremium && !fleet.fleets.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { showAddVehicle = true } label: { Label("차량 추가", systemImage: "plus") }
                            Button { showImporter = true } label: { Label("CSV 대량등록", systemImage: "square.and.arrow.down") }
                        } label: { Image(systemName: "plus.circle") }
                    }
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .task { if premium.isPremium { await fleet.loadFleets() } }
        .sheet(isPresented: $showAddVehicle) { FleetVehicleEditView(fleet: fleet, editing: nil) }
        .sheet(item: $editingVehicle) { FleetVehicleEditView(fleet: fleet, editing: $0) }
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

    // Fleet 생성
    private var createFleetState: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2.fill").font(.system(size: 40)).foregroundStyle(Theme.gold).padding(.top, 40)
            Text("조직을 만들어 시작하세요").font(pd(15, .semibold))
            TextField("회사/조직 이름 (예: OO운수)", text: $newFleetName)
                .font(pd(15)).multilineTextAlignment(.center).padding(14)
                .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                .padding(.horizontal, 24)
            Button {
                let n = newFleetName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { Task { await fleet.createFleet(name: n); newFleetName = "" } }
            } label: {
                Text("조직 만들기").font(pd(14, .semibold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).background(Theme.goldGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 24)
            }.disabled(newFleetName.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
        }
    }

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

                if fleet.vehicles.isEmpty {
                    emptyVehicles
                } else {
                    ForEach(fleet.vehicles) { v in
                        Button { editingVehicle = v } label: { vehicleRow(v) }.buttonStyle(.plain)
                    }
                }
                if let msg = importMsg {
                    Text(msg).font(pd(11)).foregroundStyle(Theme.green).padding(.top, 4)
                }
            }
            .padding(16)
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
    @State private var showDelete = false

    init(fleet: FleetStore, editing: FleetVehicle?) {
        self.fleet = fleet; self.editing = editing
        _plate = State(initialValue: editing?.plate ?? "")
        _model = State(initialValue: editing?.model ?? "")
        _year = State(initialValue: editing?.year.map(String.init) ?? "")
        _category = State(initialValue: editing?.vehicleCategory ?? .car)
        _fuel = State(initialValue: editing?.fuel ?? FuelType.gasoline.rawValue)
        _odometer = State(initialValue: String(editing?.odometerKm ?? 0))
        _driverName = State(initialValue: editing?.driverName ?? "")
        _driverPhone = State(initialValue: editing?.driverPhone ?? "")
        _memo = State(initialValue: editing?.memo ?? "")
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
                }
                Section("담당 기사") {
                    TextField("기사 이름", text: $driverName)
                    TextField("연락처", text: $driverPhone).keyboardType(.phonePad)
                    TextField("메모 (선택)", text: $memo)
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
            memo: memo.isEmpty ? nil : memo, status: "active")
        if let e = editing { await fleet.updateVehicle(id: e.id, up) } else { await fleet.addVehicle(up) }
        dismiss()
    }
}
