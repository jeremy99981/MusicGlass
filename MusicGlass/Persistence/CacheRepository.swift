import Foundation
import SwiftData

@MainActor
final class CacheRepository {
    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    func cacheRecords() throws -> [StoredCacheRecord] {
        let context = database.newContext()
        return try context.fetch(FetchDescriptor<StoredCacheRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }
}
