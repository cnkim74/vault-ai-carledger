import SwiftUI

/// 차량 정보 수정 폼 — 차종 카탈로그 참조, 소유형태별 필드 분기.
struct VehicleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore

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

    init(store: VaultStore) {
        self.store = store
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
            .navigationTitle("차량 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("저장") { Task { await save() } }
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

        var update = VaultStore.VehicleUpdate()
        update.name = name.isEmpty ? store.vehicle.name : name
        update.plate = plate.isEmpty ? nil : plate
        update.fuel_type = fuel
        update.odometer_km = Int(odometer)
        update.ownership = ownership.rawValue
        update.maker = useCustomName ? nil : maker
        update.model = useCustomName ? nil : model
        update.year = Int(year)
        switch ownership {
        case .purchase:
            update.purchase_price_won = Int(purchasePrice)
        case .lease, .rent:
            update.lease_limit_km = Int(leaseLimit)
            update.monthly_fee_won = Int(monthlyFee)
            if hasContractEnd {
                update.contract_end = df.string(from: contractEnd)
            }
        }

        do {
            try await store.updateVehicle(update)
            dismiss()
        } catch {
            errorMessage = "저장 실패: \(error.localizedDescription)"
        }
        saving = false
    }
}
