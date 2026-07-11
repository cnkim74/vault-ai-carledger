import SwiftUI

/// 신규 사용자 온보딩 — 첫 차량 등록 전까지 목업/약정 등 아무 데이터도 보이지 않는 빈 시작 화면.
struct FirstVehicleView: View {
    @ObservedObject var store: VaultStore
    var consumer: ConsumerSession? = nil
    @StateObject private var tesla = TeslaService()
    @State private var showAdd = false
    @State private var importing = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            RoundedRectangle(cornerRadius: 24).fill(Theme.gold.opacity(0.12))
                .frame(width: 92, height: 92)
                .overlay(Image(systemName: "car.2.fill").font(.system(size: 40)).foregroundStyle(Theme.gold))

            Text("Wheelet").font(pd(26, .black)).kerning(0.5).foregroundStyle(Theme.goldGradient)
            Text("첫 차량을 등록하고 시작하세요")
                .font(pd(15, .semibold)).foregroundStyle(Theme.text)
            Text("주유·정비·주행 기록과 AI 인사이트를\n내 차량에 맞춰 관리해요.")
                .font(pd(12.5)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).lineSpacing(3)

            Spacer()

            VStack(spacing: 10) {
                Button { showAdd = true } label: {
                    Label("차량 등록하기", systemImage: "plus")
                        .font(pd(15, .semibold)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.goldGradient).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button {
                    Task {
                        tesla.consumer = consumer
                        importing = true
                        let ok = await tesla.importVehicle(store: store)
                        if ok {
                            await store.load()
                            await tesla.importCharging(store: store)   // 충전 이력도 자동 임포트
                        }
                        importing = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if importing { ProgressView().controlSize(.small).tint(Theme.gold) }
                        else { Image(systemName: "bolt.car.fill").font(.system(size: 14)) }
                        Text(importing ? "테슬라에서 가져오는 중…" : "테슬라에서 가져오기").font(pd(14, .semibold))
                    }
                    .foregroundStyle(Theme.gold)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
                }
                .disabled(importing)
                if let msg = tesla.message {
                    Text(msg).font(pd(10.5)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .sheet(isPresented: $showAdd, onDismiss: { Task { await store.load() } }) {
            VehicleEditView(store: store, mode: .create)
        }
    }
}
