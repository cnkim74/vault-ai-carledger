import SwiftUI

/// 기록 추가 시트 — 차량 종류에 맞춰 충전/주유·주행·정비 입력.
struct AddRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore

    @State private var kind: RecordKind
    @State private var title = ""
    @State private var amount = ""
    @State private var volume = ""
    @State private var distance = ""
    @State private var duration = ""
    @State private var location = ""
    @State private var tag = ""
    @State private var saving = false
    @State private var errorMessage: String?

    // 전기차면 충전, 그 외엔 주유
    private var isEV: Bool { !store.vehicle.usesFuel }
    private var energyKind: RecordKind { isEV ? .charge : .fuel }

    init(store: VaultStore) {
        self.store = store
        _kind = State(initialValue: !store.vehicle.usesFuel ? .charge : .fuel)
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
                        FlowChips(items: MaintenancePresets.items(ev: isEV)) { item in
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
            }
            .navigationTitle("기록 추가")
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
            try await store.addRecord(
                kind: kind,
                title: finalTitle,
                amountWon: Int(amount),
                distanceKm: Double(distance),
                durationMin: Int(duration),
                location: location.isEmpty ? nil : location,
                tag: tag.isEmpty ? nil : tag
            )
            dismiss()
        } catch {
            errorMessage = "저장 실패: \(error.localizedDescription)"
        }
        saving = false
    }
}

/// 정비 항목 빠른 선택 칩 (줄바꿈 흐름 배치)
struct FlowChips: View {
    let items: [String]
    var onTap: (String) -> Void

    var body: some View {
        FlexibleGrid(items: items) { item in
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

/// 간단한 가변 폭 흐름 배치
struct FlexibleGrid: View {
    let items: [String]
    var content: (String) -> AnyView

    init(items: [String], @ViewBuilder content: @escaping (String) -> some View) {
        self.items = items
        self.content = { AnyView(content($0)) }
    }

    var body: some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(items, id: \.self) { item in
                    content(item)
                        .padding(.trailing, 6)
                        .padding(.bottom, 8)
                        .alignmentGuide(.leading) { d in
                            if abs(width - d.width) > geo.size.width {
                                width = 0; height -= d.height
                            }
                            let result = width
                            if item == items.last { width = 0 } else { width -= d.width }
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            if item == items.last { height = 0 }
                            return result
                        }
                }
            }
        }
        .frame(height: 140)
    }
}
