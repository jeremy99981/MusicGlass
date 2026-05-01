import Foundation
import SwiftData

@MainActor
final class PlaylistRepository {
    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    func localPlaylists() throws -> [StoredPlaylistRecord] {
        let context = database.newContext()
        return try context.fetch(FetchDescriptor<StoredPlaylistRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    func create(title: String) throws {
        let context = database.newContext()
        context.insert(StoredPlaylistRecord(title: title))
        try context.save()
    }
}
