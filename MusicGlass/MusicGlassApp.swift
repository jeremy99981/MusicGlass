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

import AppIntents

struct PlayMusicIntent: AppIntent {
    static let title: LocalizedStringResource = "Jouer de la musique sur MusicGlass"
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Morceau ou artiste")
    var searchTerm: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let container = AppContainer.live()
        let intentService = DeepSeekMusicIntentService()
        let resolver = MusicAIResolver(client: container.youTubeMusicClient)
        
        do {
            let intent = try await intentService.parseIntent(from: searchTerm)
            let resolution = try await resolver.resolve(intent: intent)
            
            switch resolution {
            case .playableTrack(let track, let queue):
                container.playerEngine.play(track, queue: queue)
            case .playableAlbum(_, let tracks):
                if let first = tracks.first { container.playerEngine.play(first, queue: tracks) }
            case .playablePlaylist(_, let tracks):
                if let first = tracks.first { container.playerEngine.play(first, queue: tracks) }
            case .playableRadio(let track):
                container.playerEngine.playRadio(from: track)
            default: break
            }
            container.playerEngine.shouldShowFullPlayer = true
        } catch {
            print("🎙️ [INTENT] Error: \(error.localizedDescription)")
        }
        
        return .result()
    }
}

struct MusicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayMusicIntent(),
            phrases: [
                "Joue de la musique sur \(.applicationName)",
                "Ouvre l'assistant de \(.applicationName)"
            ],
            shortTitle: "Jouer de la musique",
            systemImageName: "sparkles"
        )
    }
}
