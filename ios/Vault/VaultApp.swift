import SwiftUI

@main
struct VaultApp: App {
    init() {
        AppFonts.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
