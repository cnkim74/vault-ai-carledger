import SwiftUI
import PhotosUI

/// 차고 탭 — 차량 목록(전환) + 대표 차량 카드 + 정보 수정/추가
struct GarageView: View {
    @ObservedObject var store: VaultStore
    @StateObject private var tesla = TeslaService()
    @StateObject private var premium = PremiumStore()
    @State private var showOBDGuide = false
    @State private var carImage: UIImage?
    @State private var showPhotoDialog = false
    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showEdit = false
    @State private var showAdd = false

    private var v: Vehicle { store.vehicle }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("차고")
                        .font(pd(22, .black))
                        .kerning(1)
                    Spacer()
                    Button {
                        showAdd = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("차량 추가")
                                .font(pd(12, .semibold))
                        }
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .overlay(Capsule().stroke(Theme.gold.opacity(0.4), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // 차량 전환 목록 (2대 이상일 때)
                if store.vehicles.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.vehicles) { veh in
                                vehicleChip(veh)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 12)
                }

                vehicleCard
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                infoSection
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                Button {
                    showEdit = true
                } label: {
                    Text("차량 정보 수정")
                        .font(pd(14, .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.goldGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // 테슬라 연결 (전기차)
                if v.fuelType == FuelType.ev.rawValue {
                    teslaButton
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    // 연결됐으면 슈퍼차저 충전 이력 가져오기
                    if tesla.connected {
                        chargingImportButton
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                }

                // OBD 동글 자동 연동 (브랜드 무관)
                obdButton
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                Spacer(minLength: 24)
            }
        }
        .background(Theme.bgTop.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    carImage = img
                    CarImageStore.save(img, for: v.id)
                }
            }
        }
        .onChange(of: store.vehicle.id) { _, newID in
            carImage = CarImageStore.load(for: newID)
        }
        .sheet(isPresented: $showEdit) {
            VehicleEditView(store: store, mode: .edit)
        }
        .sheet(isPresented: $showAdd) {
            VehicleEditView(store: store, mode: .create)
        }
        .onAppear { carImage = CarImageStore.load(for: v.id) }
    }

    // OBD 동글 안내/연동 버튼
    private var obdButton: some View {
        Button {
            showOBDGuide = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "car.rear.and.tire.marks").font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text("OBD 동글로 자동 연동").font(pd(14, .semibold))
                    Text("브랜드 무관 · 연료·주행·정비 자동 기록").font(pd(10)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.silver)
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showOBDGuide) { OBDGuideView(premium: premium, store: store) }
    }

    // 테슬라 연결/동기화 버튼
    private var teslaButton: some View {
        Button {
            Task {
                if !tesla.connected { await tesla.connect() }
                if tesla.connected { await tesla.sync(store: store) }
            }
        } label: {
            HStack(spacing: 8) {
                if tesla.connecting || tesla.syncing {
                    ProgressView().controlSize(.small).tint(Theme.silver)
                } else {
                    Image(systemName: tesla.connected ? "arrow.triangle.2.circlepath" : "bolt.car.fill")
                        .font(.system(size: 14))
                }
                Text(tesla.connecting ? "테슬라 로그인 중…"
                     : tesla.syncing ? "동기화 중…"
                     : tesla.connected ? "테슬라 동기화 (배터리·주행거리)"
                     : "테슬라 연결")
                    .font(pd(14, .semibold))
            }
            .foregroundStyle(Theme.silver)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
        }
        .disabled(tesla.connecting || tesla.syncing)
        .overlay(alignment: .bottom) {
            if let msg = tesla.message {
                Text(msg).font(pd(10)).foregroundStyle(Theme.muted).offset(y: 16)
            }
        }
    }

    // 슈퍼차저 충전 이력 임포트 버튼
    private var chargingImportButton: some View {
        Button {
            Task { await tesla.importCharging(store: store) }
        } label: {
            HStack(spacing: 8) {
                if tesla.importing {
                    ProgressView().controlSize(.small).tint(Theme.gold)
                } else {
                    Image(systemName: "bolt.fill").font(.system(size: 13))
                }
                Text(tesla.importing ? "충전 이력 가져오는 중…" : "슈퍼차저 충전 이력 가져오기")
                    .font(pd(13, .semibold))
            }
            .foregroundStyle(Theme.gold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.4), lineWidth: 1))
        }
        .disabled(tesla.importing)
    }

    // 차량 전환 칩
    private func vehicleChip(_ veh: Vehicle) -> some View {
        let selected = veh.id == v.id
        return Button {
            store.select(veh.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: veh.vehicleCategory.icon)
                    .font(.system(size: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text(veh.name)
                        .font(pd(12, .semibold))
                        .lineLimit(1)
                    if let plate = veh.plate {
                        Text(plate)
                            .font(pd(9.5))
                            .foregroundStyle(selected ? Theme.ink.opacity(0.7) : Theme.muted)
                    }
                }
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                }
            }
            .foregroundStyle(selected ? Theme.ink : Theme.silver)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selected
                    ? AnyShapeStyle(Theme.goldGradient)
                    : AnyShapeStyle(Color.white.opacity(0.06))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // 차량 카드
    private var vehicleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 사진
            Group {
                if let img = carImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: "photo")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.gold.opacity(0.7))
                                Text("탭해서 차량 사진을 선택하세요")
                                    .font(pd(11))
                                    .foregroundStyle(Color.white.opacity(0.45))
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(Color.white.opacity(0.18))
                        )
                        .frame(height: 170)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture { showPhotoDialog = true }
            .confirmationDialog("차량 사진", isPresented: $showPhotoDialog, titleVisibility: .visible) {
                Button("앨범에서 선택") { showPicker = true }
                Button("샘플 · 레드") { setSample("car-red") }
                Button("샘플 · 블루") { setSample("car-blue") }
                Button("샘플 · 스카이") { setSample("car-sky") }
                if carImage != nil {
                    Button("사진 제거", role: .destructive) {
                        carImage = nil
                        CarImageStore.clear(for: v.id)
                    }
                }
                Button("취소", role: .cancel) {}
            }

            // 이름 + 번호판
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(v.name)
                        .font(gm(18, .medium))
                    if let maker = v.maker {
                        Text("\(maker)\(v.year.map { " · \($0)년식" } ?? "")")
                            .font(pd(11))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                if let plate = v.plate {
                    Text(plate)
                        .font(gm(12, .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 14)

            // 뱃지
            HStack(spacing: 6) {
                badge(v.ownership.label, color: Theme.gold)
                badge(L(v.fuelType), color: Theme.silver)
                if v.battery > 0 && v.fuelType == "전기차" {
                    badge(String(format: L("배터리 %d%%"), v.battery), color: Theme.green)
                }
            }
            .padding(.top, 10)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        .background(
            LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(pd(10.5, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    // 상세 정보
    private var infoSection: some View {
        VStack(spacing: 0) {
            infoRow("누적 주행", "\(grouped(v.odometerKm)) km")

            if v.ownership != .purchase {
                if let limit = v.leaseLimitKm {
                    divider
                    infoRow("약정거리", "\(grouped(v.leaseDriven)) / \(grouped(limit)) km")
                }
                if let fee = v.monthlyFeeWon {
                    divider
                    infoRow("월 납입금", won(fee))
                }
                if let start = v.contractStart {
                    divider
                    infoRow("계약 시작", start)
                }
                if let end = v.contractEnd {
                    divider
                    infoRow("계약 종료", end)
                }
                if let start = v.contractStart, let end = v.contractEnd {
                    divider
                    infoRow("계약 기간", contractTermLabel(start, end))
                }
            } else if let price = v.purchasePriceWon {
                divider
                infoRow("구매가", won(price))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }

    // 계약 기간 라벨 (예: "5년" 또는 "3년 6개월")
    private func contractTermLabel(_ start: String, _ end: String) -> String {
        guard let s = Vehicle.parseDay(start), let e = Vehicle.parseDay(end) else { return "-" }
        let c = Calendar.current.dateComponents([.year, .month], from: s, to: e)
        let y = c.year ?? 0, m = c.month ?? 0
        if y > 0 && m > 0 { return "\(y)년 \(m)개월" }
        if y > 0 { return "\(y)년" }
        return "\(m)개월"
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(L(label)).font(pd(12)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(gm(13, .medium))
        }
        .padding(.vertical, 12)
    }

    private func setSample(_ name: String) {
        guard let img = CarImageStore.sample(name) else { return }
        carImage = img
        CarImageStore.save(img, for: v.id)
    }
}
