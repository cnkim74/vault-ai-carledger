import SwiftUI

/// 차량별 주행거리 기반 정비 체크리스트 — 전체 항목·다음 정비까지 남은 거리·상태.
struct MaintenanceChecklistView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore
    @State private var showSchedule = false
    @State private var apptDate: Date = {
        let base = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        var c = Calendar.current.dateComponents([.year, .month, .day], from: base)
        c.hour = 9; c.minute = 0
        return Calendar.current.date(from: c) ?? base
    }()
    @State private var apptPlace = ""
    @State private var apptDetail = ""
    @State private var scheduling = false
    @State private var scheduleResult: String?

    private var items: [MaintenanceCheck] {
        MaintenanceSchedule.checklist(vehicle: store.vehicle, records: store.records)
    }

    /// 임박·초과 항목 (예약 메모용)
    private var dueItems: [MaintenanceCheck] {
        items.filter { $0.isOverdue || $0.isSoon }
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    scheduleButton
                    ForEach(items) { row($0) }
                    Text("정비 기록을 추가하면 그 시점 주행거리를 기준으로 다음 정비 시기를 계산해요. 알림을 켜면 시기가 다가올 때 알려드려요.")
                        .font(pd(10.5)).foregroundStyle(Theme.muted2)
                        .padding(.top, 6)
                }
                .padding(16)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("정비 체크리스트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .sheet(isPresented: $showSchedule) { scheduleSheet }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
    }

    // 정비 예약을 캘린더에 등록
    private var scheduleButton: some View {
        Button { showSchedule = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus").font(.system(size: 14))
                Text("정비 예약 캘린더에 등록").font(pd(13, .semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.gold)
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .background(Theme.gold.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var scheduleSheet: some View {
        NavigationStack {
            Form {
                Section("예약 날짜") {
                    DatePicker("예약 날짜", selection: $apptDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                Section("장소 (주소)") {
                    TextField("예: 테슬라 서비스센터 성수 / 서울 성동구 …", text: $apptPlace)
                }
                Section("정비 내역") {
                    TextField("예: 타이어 교체, 12개월 점검", text: $apptDetail, axis: .vertical)
                        .lineLimit(1...4)
                }
                if !dueItems.isEmpty {
                    Section("함께 메모될 정비 항목") {
                        ForEach(dueItems) { c in
                            HStack {
                                Text(L(c.item)).font(pd(13))
                                Spacer()
                                Text(statusText(c)).font(pd(11)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
                Section {
                    Button {
                        Task {
                            scheduling = true
                            var lines: [String] = []
                            if !apptDetail.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(apptDetail) }
                            if !apptPlace.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(L("장소: ") + apptPlace) }
                            if !dueItems.isEmpty {
                                lines.append(L("점검 항목:") + "\n" + dueItems.map { "• \(L($0.item)) (\(statusText($0)))" }.joined(separator: "\n"))
                            }
                            let notes = lines.isEmpty ? nil : lines.joined(separator: "\n\n")
                            let ok = await CalendarService().addEvent(
                                title: String(format: L("%@ 정비 예약"), store.vehicle.name),
                                date: apptDate, notes: notes,
                                location: apptPlace.isEmpty ? nil : apptPlace, alarmDaysBefore: 1)
                            scheduling = false
                            scheduleResult = ok ? L("캘린더에 등록됐어요 (하루 전 알림)") : L("캘린더 접근이 필요해요")
                            if ok { showSchedule = false }
                        }
                    } label: {
                        HStack { if scheduling { ProgressView().controlSize(.small) }
                            Text("캘린더에 등록").frame(maxWidth: .infinity) }
                    }
                    .disabled(scheduling)
                    if let msg = scheduleResult {
                        Text(msg).font(pd(11)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .navigationTitle("정비 예약")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { showSchedule = false } } }
            .tint(Theme.gold).preferredColorScheme(.dark)
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: store.vehicle.vehicleCategory.icon).font(.system(size: 15)).foregroundStyle(Theme.gold)
            Text(store.vehicle.name).font(pd(14, .semibold))
            Spacer()
            Text("\(grouped(store.vehicle.odometerKm)) km").font(gm(13, .medium)).foregroundStyle(Theme.silver)
        }
        .padding(.bottom, 2)
    }

    private func row(_ c: MaintenanceCheck) -> some View {
        let color: Color = c.isOverdue ? Theme.red : (c.isSoon ? Theme.orange : (c.remainingKm == nil ? Theme.muted : Theme.green))
        return HStack(spacing: 12) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(c.item)).font(pd(13.5, .medium))
                Text(String(format: L("주기 %@km"), grouped(c.intervalKm)))
                    .font(pd(10)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(statusText(c))
                .font(gm(12, .medium)).foregroundStyle(color)
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(c.remainingKm == nil ? 0.12 : 0.3), lineWidth: 1))
    }

    private func statusText(_ c: MaintenanceCheck) -> String {
        guard let r = c.remainingKm else { return L("기록 없음") }
        return r < 0 ? String(format: L("%dkm 초과"), -r) : String(format: L("%dkm 남음"), r)
    }
}
