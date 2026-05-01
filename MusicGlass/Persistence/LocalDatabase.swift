import Foundation
import SwiftData

@MainActor
final class LocalDatabase {
    let modelContainer: ModelContainer

    private init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    static func live() -> LocalDatabase {
        do {
            let schema = Schema([
                StoredTrackRecord.self,
                StoredPlaylistRecord.self,
                StoredCacheRecord.self
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return LocalDatabase(modelContainer: container)
        } catch {
            AppLogger.persistence.fault("SwiftData failed: \(error.localizedDescription, privacy: .public)")
            let schema = Schema([StoredTrackRecord.self, StoredPlaylistRecord.self, StoredCacheRecord.self])
            let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            return LocalDatabase(modelContainer: container)
        }
    }

    func newContext() -> ModelContext {
        ModelContext(modelContainer)
    }
}
