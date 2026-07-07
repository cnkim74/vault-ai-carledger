import SwiftUI

/// 메인 셸 — 하단 탭바로 홈/기록/통계/차고 전환, 중앙 +로 기록 추가.
/// 환경변수 TAB=records|stats|garage로 시작 탭 지정 가능 (테스트용).
struct ContentView: View {
    @StateObject private var store = VaultStore()
    @StateObject private var insight = InsightService()
    @StateObject private var profile = ProfileStore()
    @StateObject private var premium = PremiumStore()
    @State private var tab: MainTab =
        MainTab(rawValue: ProcessInfo.processInfo.environment["TAB"] ?? "") ?? .home
    @State private var showAddRecord = false
    @State private var showProfile = false
    @State private var showAccount = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .home: CockpitView(store: store, insight: insight, profile: profile,
                                        onEditProfile: { showAccount = true },
                                        onShowRecords: { tab = .records })
                case .records: RecordsListView(store: store)
                case .stats: BriefingView(store: store, insight: insight)
                case .garage: GarageView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBarView(tab: $tab) { showAddRecord = true }
        }
        .background(Theme.bgTop.ignoresSafeArea())
        .sheet(isPresented: $showAddRecord) {
            AddRecordView(store: store)
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheet(profile: profile)
        }
        .sheet(isPresented: $showAccount) {
            AccountView(profile: profile, premium: premium)
        }
        .task {
            await store.load()
            await store.loadPlaces()
            await insight.generate(vehicle: store.vehicle, records: store.records)
        }
        .onAppear {
            if !profile.isSet { showProfile = true }   // 첫 실행 온보딩
        }
    }
}

#Preview {
    ContentView()
}
