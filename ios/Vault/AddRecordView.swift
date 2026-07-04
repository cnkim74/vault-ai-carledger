import SwiftUI

/// 기록 추가 시트 — 충전/주행/정비 종류별 입력 폼.
struct AddRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore

    @State private var kind: RecordKind = .charge
    @State private var title = ""
    @State private var amount = ""
    @State private var distance = ""
    @State private var duration = ""
    @State private var location = ""
    @State private var tag = ""
    @State private var saving = false
    @State private var errorMessage: String?

    private var defaultTitle: String {
        switch kind {
        case .charge: return "충전"
        case .drive: return "주행 일지"
        case .maintenance: return "정비"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("종류") {
                    Picker("종류", selection: $kind) {
                        Text("충전").tag(RecordKind.charge)
                        Text("주행").tag(RecordKind.drive)
                        Text("정비").tag(RecordKind.maintenance)
                    }
                    .pickerStyle(.segmented)
                }

                Section("내용") {
                    TextField("제목 (예: 초급속 충전 · 42kWh)", text: $title)

                    switch kind {
                    case .charge:
                        TextField("금액 (원)", text: $amount)
                            .keyboardType(.numberPad)
                        TextField("장소 (예: 이마트 성수)", text: $location)
                    case .drive:
                        TextField("거리 (km)", text: $distance)
                            .keyboardType(.decimalPad)
                        TextField("소요 시간 (분)", text: $duration)
                            .keyboardType(.numberPad)
                        TextField("태그 (예: 출퇴근)", text: $tag)
                    case .maintenance:
                        TextField("차량/위치 (예: 세컨카)", text: $location)
                        TextField("메모 (예: 2,000km 남음)", text: $tag)
                    }
                }

                if let msg = errorMessage {
                    Section {
                        Text(msg).foregroundStyle(.red).font(pd(12))
                    }
                }

                if !store.live {
                    Section {
                        Text("Supabase 미연결 상태 — 저장하려면 연결이 필요해요.")
                            .foregroundStyle(Theme.muted)
                            .font(pd(12))
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
        do {
            try await store.addRecord(
                kind: kind,
                title: title.isEmpty ? defaultTitle : title,
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
