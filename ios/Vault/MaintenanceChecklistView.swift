import SwiftUI

/// 차량별 주행거리 기반 정비 체크리스트 — 전체 항목·다음 정비까지 남은 거리·상태.
struct MaintenanceChecklistView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore

    private var items: [MaintenanceCheck] {
        MaintenanceSchedule.checklist(vehicle: store.vehicle, records: store.records)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
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
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
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
