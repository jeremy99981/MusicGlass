import SwiftData
import SwiftUI

@main
struct MusicGlassApp: App {
    @StateObject private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(container.playerEngine)
                .modelContainer(container.localDatabase.modelContainer)
        }
    }
}
