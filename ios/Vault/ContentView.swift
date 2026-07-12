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
    @StateObject private var adminStore = AdminStore()
    @StateObject private var consumer = ConsumerSession()
    @Environment(\.scenePhase) private var scenePhase
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

    /// 차량 0대 = 신규 사용자 → 첫 차량 등록 온보딩 (목업/약정 미표시)
    private var needsFirstVehicle: Bool {
        store.vehicles.isEmpty && myWorkVehicles.isEmpty
    }

    // 최초 로드 전 로딩 스플래시 (목업 플래시 방지)
    private var loadingSplash: some View {
        VStack(spacing: 14) {
            Text("Wheelet").font(pd(24, .black)).foregroundStyle(Theme.goldGradient)
            ProgressView().tint(Theme.gold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var mainShell: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .home:
                    CockpitView(store: store, insight: insight, profile: profile,
                                fleet: fleet, workVehicles: myWorkVehicles, workVehicleID: $workVehicleID,
                                adminPending: adminStore.isAdmin ? adminStore.pendingCount : 0,
                                consumer: consumer,
                                onEditProfile: { showAccount = true },
                                onShowRecords: { tab = .records })
                case .records: RecordsListView(store: store)
                case .stats: BriefingView(store: store, insight: insight)
                case .garage: GarageView(store: store, consumer: consumer)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBarView(tab: $tab) {
                if let wv = workVehicle, tab == .home { workRecordVehicle = wv }
                else { showAddRecord = true }
            }
        }
    }

    var body: some View {
        Group {
            if !store.loadedOnce && store.vehicles.isEmpty {
                loadingSplash
            } else if needsFirstVehicle {
                FirstVehicleView(store: store, consumer: consumer)
            } else {
                mainShell
            }
        }
        .background(Theme.bgTop.ignoresSafeArea())
        .sheet(isPresented: $showAddRecord) {
            AddRecordView(store: store, consumer: consumer)
        }
        .sheet(item: $workRecordVehicle) { FleetRecordAddView(fleet: fleet, vehicle: $0) }
        .sheet(isPresented: $showProfile) {
            ProfileSheet(profile: profile)
        }
        .sheet(isPresented: $showAccount) {
            AccountView(profile: profile, premium: premium, fleet: fleet, auth: auth, adminStore: adminStore)
        }
        .task {
            store.session = consumer            // 개인 데이터 격리(익명 세션) 연결
            await consumer.start()              // 기기별 익명 로그인
            await store.load()
            await store.loadPlaces()
            // 차량이 있을 때만 인사이트 생성 (빈 상태에서 불필요한 AI 호출 방지)
            if !store.vehicles.isEmpty {
                await insight.generate(vehicle: store.vehicle, records: store.records)
            }
        }
        .task {
            fleet.auth = auth
            if auth.isAuthenticated { await fleet.load(uid: auth.userID) }
        }
        .task { await adminStore.refresh(auth: auth) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await adminStore.refresh(auth: auth) } }
        }
        .onChange(of: auth.isAuthenticated) { _, _ in Task { await adminStore.refresh(auth: auth) } }
        .onAppear {
            if !profile.isSet { showProfile = true }   // 첫 실행 온보딩
        }
    }
}

#Preview {
    ContentView()
}
