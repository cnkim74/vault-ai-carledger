import SwiftUI
import CoreBluetooth

/// OBD 동글 연결 → 값 읽기 → 차량에 반영.
struct OBDConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VaultStore
    @StateObject private var obd = OBDManager()
    @State private var applied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if obd.poweredOff {
                        note(L("블루투스를 켜주세요."), color: Theme.orange)
                    }

                    switch obd.phase {
                    case .idle:
                        scanButton
                    case .scanning:
                        scanning
                    case .connecting, .initializing, .reading:
                        working
                    case .done:
                        resultCard
                    case .failed:
                        note(obd.status ?? L("연결에 실패했어요"), color: Theme.orange)
                        scanButton
                    }
                }
                .padding(20)
            }
            .background(Theme.bgTop.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .navigationTitle("OBD 동글 연결")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { obd.disconnect(); dismiss() }
                }
            }
        }
        .tint(Theme.gold)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12).fill(Theme.gold.opacity(0.14)).frame(width: 44, height: 44)
                .overlay(Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 18)).foregroundStyle(Theme.gold))
            Text("동글을 꽂고 시동을 켠 뒤 스캔하세요").font(pd(12.5)).foregroundStyle(Theme.muted)
        }
    }

    private var scanButton: some View {
        Button { obd.startScan() } label: {
            Text("동글 검색")
                .font(pd(15, .semibold)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Theme.goldGradient).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var scanning: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Theme.gold)
                Text("주변 동글 검색 중…").font(pd(13)).foregroundStyle(Theme.silver)
            }
            ForEach(obd.found, id: \.identifier) { p in
                Button { obd.connect(p) } label: {
                    HStack {
                        Image(systemName: "wave.3.right").foregroundStyle(Theme.gold)
                        Text(p.name ?? "OBD").font(pd(13.5, .medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    .padding(12).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            if obd.found.isEmpty {
                Text("BLE 동글이 보이지 않으면, 동글이 켜져 있고 iOS 호환(BLE)인지 확인하세요.")
                    .font(pd(11)).foregroundStyle(Theme.muted).padding(.top, 4)
            }
        }
    }

    private var working: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(Theme.gold)
            Text(obd.status ?? L("연결 중…")).font(pd(13)).foregroundStyle(Theme.silver)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var resultCard: some View {
        let r = obd.reading
        VStack(alignment: .leading, spacing: 12) {
            Text(obd.status ?? L("읽기 완료")).font(pd(13, .semibold)).foregroundStyle(Theme.gold)

            valueRow("연료 잔량", r?.fuelPercent.map { "\($0)%" })
            valueRow("누적 주행", r?.odometerKm.map { "\(grouped($0)) km" })
            valueRow("주행 트립", r?.tripKm.map { "\(grouped(Int($0))) km" })
            valueRow("VIN", r?.vin)

            if let odo = r?.odometerKm {
                Button {
                    Task { try? await store.updateVehicle(.init(odometer_km: odo)); applied = true }
                } label: {
                    Text(applied ? "반영됨" : "누적 주행을 차량에 반영")
                        .font(pd(14, .semibold)).foregroundStyle(applied ? Theme.silver : Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(applied ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(Theme.goldGradient))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(applied)
                .padding(.top, 4)
            }

            Button { obd.disconnect() } label: {
                Text("다시 검색").font(pd(12)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity).padding(.top, 2)
        }
        .padding(14).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private func valueRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(L(label)).font(pd(12)).foregroundStyle(Theme.muted)
            Spacer()
            Text(value ?? "—").font(gm(13, .medium)).foregroundStyle(value == nil ? Theme.muted : Theme.text)
        }
        .padding(.vertical, 2)
    }

    private func note(_ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(color)
            Text(text).font(pd(12)).foregroundStyle(Theme.silver)
        }
        .padding(12).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
