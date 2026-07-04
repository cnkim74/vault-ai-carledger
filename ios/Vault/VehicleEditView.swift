import SwiftUI

/// 차량 정보 수정/등록 폼 — 차종 카탈로그 참조, 소유형태별 필드 분기.
struct VehicleEditView: View {
    enum Mode {
        case edit, create
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore
    let mode: Mode

    @State private var maker: String
    @State private var model: String
    @State private var customName: String
    @State private var useCustomName: Bool
    @State private var plate: String
    @State private var fuel: String
    @State private var year: String
    @State private var odometer: String
    @State private var ownership: Ownership
    @State private var purchasePrice: String
    @State private var monthlyFee: String
    @State private var leaseLimit: String
    @State private var contractEnd: Date
    @State private var hasContractEnd: Bool
    @State private var saving = false
    @State private var errorMessage: String?

    init(store: VaultStore, mode: Mode = .edit) {
        self.store = store
        self.mode = mode

        if mode == .create {
            _maker = State(initialValue: CarCatalog.makers[0])
            _model = State(initialValue: CarCatalog.models(for: CarCatalog.makers[0]).first ?? "")
            _useCustomName = State(initialValue: false)
            _customName = State(initialValue: "")
            _plate = State(initialValue: "")
            _fuel = State(initialValue: FuelType.gasoline.rawValue)
            _year = State(initialValue: "")
            _odometer = State(initialValue: "0")
            _ownership = State(initialValue: .purchase)
            _purchasePrice = State(initialValue: "")
            _monthlyFee = State(initialValue: "")
            _leaseLimit = State(initialValue: "")
            _contractEnd = State(initialValue: Date())
            _hasContractEnd = State(initialValue: false)
            return
        }

        let v = store.vehicle
        let knownMaker = v.maker.flatMap { CarCatalog.makers.contains($0) ? $0 : nil }
        _maker = State(initialValue: knownMaker ?? CarCatalog.makers[0])
        let models = CarCatalog.models(for: knownMaker ?? CarCatalog.makers[0])
        let knownModel = v.model.flatMap { models.contains($0) ? $0 : nil }
        _model = State(initialValue: knownModel ?? models.first ?? "")
        _useCustomName = State(initialValue: knownMaker == nil || knownModel == nil)
        _customName = State(initialValue: v.name)
        _plate = State(initialValue: v.plate ?? "")
        _fuel = State(initialValue: v.fuelType)
        _year = State(initialValue: v.year.map(String.init) ?? "")
        _odometer = State(initialValue: String(v.odometerKm))
        _ownership = State(initialValue: v.ownership)
        _purchasePrice = State(initialValue: v.purchasePriceWon.map(String.init) ?? "")
        _monthlyFee = State(initialValue: v.monthlyFeeWon.map(String.init) ?? "")
        _leaseLimit = State(initialValue: v.leaseLimitKm.map(String.init) ?? "")
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let end = v.contractEnd.flatMap { df.date(from: $0) }
        _contractEnd = State(initialValue: end ?? Date())
        _hasContractEnd = State(initialValue: end != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("차량") {
                    Toggle("직접 입력", isOn: $useCustomName)
                    if useCustomName {
                        TextField("차량 이름 (예: Model Y Long Range)", text: $customName)
                    } else {
                        Picker("제조사", selection: $maker) {
                            ForEach(CarCatalog.makers, id: \.self) { Text($0).tag($0) }
                        }
                        .onChange(of: maker) { _, newMaker in
                            model = CarCatalog.models(for: newMaker).first ?? ""
                        }
                        Picker("모델", selection: $model) {
                            ForEach(CarCatalog.models(for: maker), id: \.self) { Text($0).tag($0) }
                        }
                    }
                    TextField("연식 (예: 2024)", text: $year)
                        .keyboardType(.numberPad)
                }

                Section("등록 정보") {
                    TextField("차량 번호 (예: 62가 3817)", text: $plate)
                    Picker("연료", selection: $fuel) {
                        ForEach(FuelType.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    TextField("누적 주행 (km)", text: $odometer)
                        .keyboardType(.numberPad)
                }

                Section("소유 형태") {
                    Picker("소유 형태", selection: $ownership) {
                        ForEach(Ownership.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch ownership {
                    case .purchase:
                        TextField("구매가 (원)", text: $purchasePrice)
                            .keyboardType(.numberPad)
                    case .lease, .rent:
                        TextField("약정거리 (km)", text: $leaseLimit)
                            .keyboardType(.numberPad)
                        TextField("월 납입금 (원)", text: $monthlyFee)
                            .keyboardType(.numberPad)
                        Toggle("계약 종료일 설정", isOn: $hasContractEnd)
                        if hasContractEnd {
                            DatePicker("계약 종료일", selection: $contractEnd, displayedComponents: .date)
                        }
                    }
                }

                if let msg = errorMessage {
                    Section { Text(msg).foregroundStyle(.red).font(pd(12)) }
                }

                if !store.live {
                    Section {
                        Text("Supabase 미연결 상태 — 저장하려면 연결이 필요해요.")
                            .foregroundStyle(Theme.muted)
                            .font(pd(12))
                    }
                }
            }
            .navigationTitle(mode == .create ? "차량 추가" : "차량 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button(mode == .create ? "등록" : "저장") { Task { await save() } }
                            .disabled(!store.live)
                    }
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
    }

    private func save() async {
        saving = true
        errorMessage = nil

        let name = useCustomName ? customName : model
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        var upsert = VaultStore.VehicleUpsert()
        upsert.name = name.isEmpty ? (mode == .create ? "내 차" : store.vehicle.name) : name
        upsert.plate = plate.isEmpty ? nil : plate
        upsert.fuel_type = fuel
        upsert.odometer_km = Int(odometer)
        upsert.ownership = ownership.rawValue
        upsert.maker = useCustomName ? nil : maker
        upsert.model = useCustomName ? nil : model
        upsert.year = Int(year)
        switch ownership {
        case .purchase:
            upsert.purchase_price_won = Int(purchasePrice)
        case .lease, .rent:
            upsert.lease_limit_km = Int(leaseLimit)
            upsert.monthly_fee_won = Int(monthlyFee)
            if hasContractEnd {
                upsert.contract_end = df.string(from: contractEnd)
            }
        }

        do {
            switch mode {
            case .edit:
                try await store.updateVehicle(upsert)
            case .create:
                upsert.battery = fuel == FuelType.ev.rawValue ? 100 : 0
                try await store.addVehicle(upsert)
            }
            dismiss()
        } catch {
            errorMessage = "저장 실패: \(error.localizedDescription)"
        }
        saving = false
    }
}
