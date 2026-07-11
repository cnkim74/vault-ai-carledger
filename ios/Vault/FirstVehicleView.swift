import SwiftUI

/// 신규 사용자 온보딩 — 첫 차량 등록 전까지 목업/약정 등 아무 데이터도 보이지 않는 빈 시작 화면.
struct FirstVehicleView: View {
    @ObservedObject var store: VaultStore
    @State private var showAdd = false

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

            Button { showAdd = true } label: {
                Label("차량 등록하기", systemImage: "plus")
                    .font(pd(15, .semibold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Theme.goldGradient).clipShape(RoundedRectangle(cornerRadius: 14))
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
