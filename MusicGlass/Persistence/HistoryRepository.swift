import Foundation
import SwiftData

@MainActor
final class HistoryRepository {
    private let database: LocalDatabase
    private let maxHistoryCount = 100

    init(database: LocalDatabase) {
        self.database = database
    }

    func add(_ track: Track) throws {
        let context = database.newContext()
        let recordId = "\(StoredTrackKind.history.rawValue)-\(track.id)"
        if let existing = try fetchRecord(id: recordId, in: context) {
            existing.update(from: track, incrementPlayCount: true)
        } else {
            context.insert(StoredTrackRecord(kind: .history, track: track))
        }
        try context.save()
        try trimHistory(in: context)
    }

    func recentlyPlayed(source: String? = nil) throws -> [Track] {
        let context = database.newContext()
        var descriptor = FetchDescriptor<StoredTrackRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = maxHistoryCount
        let results = try context.fetch(descriptor).filter { $0.kind == .history }
        if let source = source {
            return results.filter { $0.sourceRaw == source }.map { $0.toTrack() }
        }
        return results.map { $0.toTrack() }
    }

    func allHistoryRecords() throws -> [StoredTrackRecord] {
        let context = database.newContext()
        return try context.fetch(FetchDescriptor<StoredTrackRecord>()).filter { $0.kind == .history }
    }

    func delete(_ track: Track) throws {
        let context = database.newContext()
        let recordId = "\(StoredTrackKind.history.rawValue)-\(track.id)"
        if let record = try fetchRecord(id: recordId, in: context) {
            context.delete(record)
            try context.save()
        }
    }

    func clear() throws {
        let context = database.newContext()
        for record in try context.fetch(FetchDescriptor<StoredTrackRecord>()).filter({ $0.kind == .history }) {
            context.delete(record)
        }
        try context.save()
    }

    private func trimHistory(in context: ModelContext) throws {
        let records = try context.fetch(FetchDescriptor<StoredTrackRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
            .filter { $0.kind == .history }
        for record in records.dropFirst(maxHistoryCount) {
            context.delete(record)
        }
        try context.save()
    }

    private func fetchRecord(id: String, in context: ModelContext) throws -> StoredTrackRecord? {
        var descriptor = FetchDescriptor<StoredTrackRecord>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first { $0.id == id }
    }
}
