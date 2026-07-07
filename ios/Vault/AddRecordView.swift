import SwiftUI
import PhotosUI

/// 기록 추가 시트 — 차량 종류에 맞춰 충전/주유·주행·정비 입력.
struct AddRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore
    @StateObject private var premium = PremiumStore()
    @StateObject private var scanner = ReceiptScanner()

    let editing: VaultRecord?

    // 스캔(프리미엄) 관련
    @State private var showScanDialog = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var scanPhotoItem: PhotosPickerItem?
    @State private var showPaywall = false

    @State private var kind: RecordKind
    @State private var title: String
    @State private var amount: String
    @State private var volume = ""
    @State private var distance: String
    @State private var duration: String
    @State private var location: String
    @State private var tag: String
    @State private var saving = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    // 전기차면 충전, 그 외엔 주유
    private var isEV: Bool { !store.vehicle.usesFuel }
    private var energyKind: RecordKind { isEV ? .charge : .fuel }
    private var isEditing: Bool { editing != nil }

    init(store: VaultStore, editing: VaultRecord? = nil) {
        self.store = store
        self.editing = editing
        _kind = State(initialValue: editing?.kind ?? (!store.vehicle.usesFuel ? .charge : .fuel))
        _title = State(initialValue: editing?.title ?? "")
        _amount = State(initialValue: editing?.amountWon.map(String.init) ?? "")
        _distance = State(initialValue: editing?.distanceKm.map { String($0) } ?? "")
        _duration = State(initialValue: editing?.durationMin.map(String.init) ?? "")
        _location = State(initialValue: editing?.location ?? "")
        _tag = State(initialValue: editing?.tag ?? "")
    }

    private var defaultTitle: String {
        switch kind {
        case .charge: return "충전"
        case .fuel: return "주유"
        case .drive: return "주행 일지"
        case .maintenance: return "정비"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // 영수증·충전 화면 스캔 → AI 자동입력 (프리미엄)
                if !isEditing {
                    Section {
                        Button {
                            if premium.isPremium { showScanDialog = true } else { showPaywall = true }
                        } label: {
                            HStack(spacing: 10) {
                                if scanner.scanning {
                                    ProgressView().controlSize(.small).tint(Theme.gold)
                                } else {
                                    Image(systemName: "camera.viewfinder").font(.system(size: 16)).foregroundStyle(Theme.gold)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(scanner.scanning ? "인식 중…" : "영수증·충전 화면 스캔")
                                        .font(pd(14, .semibold)).foregroundStyle(Theme.text)
                                    Text(premium.isPremium ? "촬영하면 AI가 자동으로 채워요" : "프리미엄 · 촬영으로 자동입력")
                                        .font(pd(10.5)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if !premium.isPremium {
                                    Image(systemName: "crown.fill").font(.system(size: 12)).foregroundStyle(Theme.gold)
                                }
                            }
                        }
                        .disabled(scanner.scanning)
                        if let err = scanner.error {
                            Text(err).font(pd(11)).foregroundStyle(.red)
                        }
                    }
                }

                Section("종류") {
                    Picker("종류", selection: $kind) {
                        Text(energyKind.label).tag(energyKind)
                        Text("주행").tag(RecordKind.drive)
                        Text("정비").tag(RecordKind.maintenance)
                    }
                    .pickerStyle(.segmented)
                }

                Section("내용") {
                    TextField(titlePlaceholder, text: $title)

                    switch kind {
                    case .charge:
                        TextField("충전량 (kWh)", text: $volume).keyboardType(.decimalPad)
                        TextField("금액 (원)", text: $amount).keyboardType(.numberPad)
                        TextField("장소 (예: 이마트 성수)", text: $location)
                    case .fuel:
                        TextField("주유량 (L)", text: $volume).keyboardType(.decimalPad)
                        TextField("금액 (원)", text: $amount).keyboardType(.numberPad)
                        TextField("주유소 (예: GS칼텍스 역삼)", text: $location)
                    case .drive:
                        TextField("거리 (km)", text: $distance).keyboardType(.decimalPad)
                        TextField("소요 시간 (분)", text: $duration).keyboardType(.numberPad)
                        TextField("태그 (예: 출퇴근)", text: $tag)
                    case .maintenance:
                        TextField("금액 (원)", text: $amount).keyboardType(.numberPad)
                        TextField("정비소 (예: 테슬라 서비스센터)", text: $location)
                    }
                }

                // 정비: 차량 종류에 맞는 예상 정비 항목 빠른 선택
                if kind == .maintenance {
                    Section("예상 정비 항목") {
                        FlowChips(items: MaintenancePresets.items(ev: isEV).map { L($0) }) { item in
                            title = item
                        }
                    }
                }

                if let msg = errorMessage {
                    Section { Text(msg).foregroundStyle(.red).font(pd(12)) }
                }
                if !store.live {
                    Section {
                        Text("Supabase 미연결 상태 — 저장하려면 연결이 필요해요.")
                            .foregroundStyle(Theme.muted).font(pd(12))
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack { Spacer(); Text("기록 삭제"); Spacer() }
                        }
                        .disabled(!store.live)
                    }
                }
            }
            .navigationTitle(isEditing ? "기록 수정" : "기록 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() }
                    else { Button("저장") { Task { await save() } }.disabled(!store.live) }
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
        .confirmationDialog("이 기록을 삭제할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("기록 삭제", role: .destructive) { Task { await remove() } }
            Button("취소", role: .cancel) {}
        }
        .confirmationDialog("스캔할 이미지", isPresented: $showScanDialog, titleVisibility: .visible) {
            Button("카메라로 촬영") { showCamera = true }
            Button("앨범에서 선택") { showPhotoPicker = true }
            Button("취소", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in Task { await handleScan(img) } }
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $scanPhotoItem, matching: .images)
        .onChange(of: scanPhotoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await handleScan(img)
                }
                scanPhotoItem = nil
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallSheet(premium: premium) }
    }

    /// 스캔 결과로 폼 필드 자동 채움.
    private func handleScan(_ image: UIImage) async {
        guard let s = await scanner.scan(image) else { return }
        kind = s.kind
        if let t = s.title { title = t }
        if let a = s.amountWon { amount = String(a) }
        if let q = s.quantity { volume = String(q) }
        if let d = s.distanceKm { distance = String(d) }
        if let loc = s.location { location = loc }
    }

    private var titlePlaceholder: String {
        switch kind {
        case .charge: return "제목 (예: 초급속 충전 · 42kWh)"
        case .fuel: return "제목 (예: 휘발유 · 40L)"
        case .drive: return "제목 (예: 서울 → 판교)"
        case .maintenance: return "제목 (아래에서 선택하거나 직접 입력)"
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil

        // 충전량/주유량은 제목 뒤에 덧붙여 저장
        var finalTitle = title.isEmpty ? defaultTitle : title
        if (kind == .charge || kind == .fuel), !volume.isEmpty, !title.contains(volume) {
            let unit = kind == .charge ? "kWh" : "L"
            finalTitle += " · \(volume)\(unit)"
        }

        do {
            if let editing {
                try await store.updateRecord(
                    id: editing.id, kind: kind, title: finalTitle,
                    amountWon: Int(amount), distanceKm: Double(distance), durationMin: Int(duration),
                    location: location.isEmpty ? nil : location, tag: tag.isEmpty ? nil : tag
                )
            } else {
                try await store.addRecord(
                    kind: kind, title: finalTitle,
                    amountWon: Int(amount), distanceKm: Double(distance), durationMin: Int(duration),
                    location: location.isEmpty ? nil : location, tag: tag.isEmpty ? nil : tag
                )
            }
            dismiss()
        } catch {
            errorMessage = "저장 실패: \(error.localizedDescription)"
        }
        saving = false
    }

    private func remove() async {
        guard let editing else { return }
        saving = true; errorMessage = nil
        do {
            try await store.deleteRecord(id: editing.id)
            dismiss()
        } catch {
            errorMessage = "삭제 실패: \(error.localizedDescription)"
        }
        saving = false
    }
}

/// 정비 항목 빠른 선택 칩 (자동 줄바꿈 · 콘텐츠에 맞춰 높이 조절)
struct FlowChips: View {
    let items: [String]
    var onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(pd(12))
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Theme.gold.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
