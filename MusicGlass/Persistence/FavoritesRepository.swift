import Foundation
import SwiftData

@MainActor
final class FavoriteRepository {
    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    func allFavorites() throws -> [Track] {
        let records = try records(kind: .favorite)
        let favoriteIds = Set(records.map(\.trackId))
        return records.map { $0.toTrack(isLiked: favoriteIds.contains($0.trackId)) }
    }

    func isFavorite(_ track: Track) throws -> Bool {
        try records(kind: .favorite).contains { $0.trackId == track.id }
    }

    @discardableResult
    func toggle(_ track: Track) throws -> Bool {
        let context = database.newContext()
        let recordId = "\(StoredTrackKind.favorite.rawValue)-\(track.id)"
        if let existing = try fetchRecord(id: recordId, in: context) {
            context.delete(existing)
            try context.save()
            return false
        } else {
            context.insert(StoredTrackRecord(kind: .favorite, track: track))
            try context.save()
            return true
        }
    }

    private func records(kind: StoredTrackKind) throws -> [StoredTrackRecord] {
        let context = database.newContext()
        var descriptor = FetchDescriptor<StoredTrackRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 500
        return try context.fetch(descriptor).filter { $0.kind == kind }
    }

    private func fetchRecord(id: String, in context: ModelContext) throws -> StoredTrackRecord? {
        var descriptor = FetchDescriptor<StoredTrackRecord>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first { $0.id == id }
    }
}
