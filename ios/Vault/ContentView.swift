import SwiftUI

/// 좌우 스와이프로 두 시안(1a 콕핏형 ↔ 1b 브리핑형)을 전환한다.
/// 환경변수 VARIANT=1b로 시작 화면 지정 가능 (테스트용).
struct ContentView: View {
    @StateObject private var store = VaultStore()
    @State private var selection: Int =
        ProcessInfo.processInfo.environment["VARIANT"] == "1b" ? 1 : 0

    var body: some View {
        TabView(selection: $selection) {
            CockpitView(store: store).tag(0)
            BriefingView(store: store).tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.bgTop.ignoresSafeArea())
        .task { await store.load() }
    }
}

#Preview {
    ContentView()
}
