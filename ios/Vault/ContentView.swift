import SwiftUI

/// 메인 셸 — 하단 탭바로 홈/기록/통계/차고 전환, 중앙 +로 기록 추가.
/// 환경변수 TAB=records|stats|garage로 시작 탭 지정 가능 (테스트용).
struct ContentView: View {
    @StateObject private var store = VaultStore()
    @StateObject private var insight = InsightService()
    @StateObject private var profile = ProfileStore()
    @StateObject private var premium = PremiumStore()
    @StateObject private var fleet = FleetStore()
    @StateObject private var auth = AuthService()
    @State private var tab: MainTab =
        MainTab(rawValue: ProcessInfo.processInfo.environment["TAB"] ?? "") ?? .home
    @State private var showAddRecord = false
    @State private var showProfile = false
    @State private var showAccount = false
    /// 업무(Fleet 배정) 차량이 선택되면 홈이 업무 모드로 전환. nil이면 개인 모드.
    @State private var workVehicleID: UUID?
    @State private var workRecordVehicle: FleetVehicle?

    /// 내게 배정된 업무 차량 (다대다 배정 기준)
    private var myWorkVehicles: [FleetVehicle] {
        guard let uid = auth.userID else { return [] }
        let ids = fleet.assignedVehicleIds(userId: uid)
        return fleet.vehicles.filter { ids.contains($0.id) }
    }
    private var workVehicle: FleetVehicle? {
        workVehicleID.flatMap { id in myWorkVehicles.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .home:
                    CockpitView(store: store, insight: insight, profile: profile,
                                fleet: fleet, workVehicles: myWorkVehicles, workVehicleID: $workVehicleID,
                                onEditProfile: { showAccount = true },
                                onShowRecords: { tab = .records })
                case .records: RecordsListView(store: store)
                case .stats: BriefingView(store: store, insight: insight)
                case .garage: GarageView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBarView(tab: $tab) {
                // 업무 모드에서 +는 해당 업무 차량의 Fleet 기록 추가
                if let wv = workVehicle, tab == .home { workRecordVehicle = wv }
                else { showAddRecord = true }
            }
        }
        .background(Theme.bgTop.ignoresSafeArea())
        .sheet(isPresented: $showAddRecord) {
            AddRecordView(store: store)
        }
        .sheet(item: $workRecordVehicle) { FleetRecordAddView(fleet: fleet, vehicle: $0) }
        .sheet(isPresented: $showProfile) {
            ProfileSheet(profile: profile)
        }
        .sheet(isPresented: $showAccount) {
            AccountView(profile: profile, premium: premium, fleet: fleet, auth: auth)
        }
        .task {
            await store.load()
            await store.loadPlaces()
            await insight.generate(vehicle: store.vehicle, records: store.records)
        }
        .task {
            fleet.auth = auth
            if auth.isAuthenticated { await fleet.load(uid: auth.userID) }
        }
        .onAppear {
            if !profile.isSet { showProfile = true }   // 첫 실행 온보딩
        }
    }
}

#Preview {
    ContentView()
}
