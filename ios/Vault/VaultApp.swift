import SwiftUI

@main
struct VaultApp: App {
    init() {
        AppFonts.registerAll()
        #if DEBUG
        // 스크린샷 캡처용 상태 주입 (환경변수, 배포 빌드엔 영향 없음)
        let env = ProcessInfo.processInfo.environment
        if env["TESLA"] == "1" { UserDefaults.standard.set(true, forKey: "tesla.connected") }
        if env["CAPTURE"] == "1" {
            if (UserDefaults.standard.string(forKey: "vault.userName") ?? "").isEmpty {
                UserDefaults.standard.set("채현", forKey: "vault.userName")  // 온보딩 시트 건너뛰기
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
