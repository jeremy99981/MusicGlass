import Foundation
import SwiftUI

enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case one
    case all

    mutating func advance() {
        switch self {
        case .off: self = .one
        case .one: self = .all
        case .all: self = .off
        }
    }

    var symbolName: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }
}

struct PlayerQueue: Codable, Hashable, Sendable {
    var tracks: [Track] = []
    var currentIndex: Int?
    var repeatMode: RepeatMode = .off
    var shuffleEnabled: Bool = false

    var currentTrack: Track? {
        guard let currentIndex, tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    var upcomingTracks: [Track] {
        guard let currentIndex, tracks.indices.contains(currentIndex) else { return tracks }
        return Array(tracks.dropFirst(currentIndex + 1))
    }

    mutating func replace(with tracks: [Track], startingAt track: Track) {
        self.tracks = tracks.isEmpty ? [track] : tracks.uniquedBy(\.id)
        self.currentIndex = self.tracks.firstIndex(where: { $0.id == track.id }) ?? 0
    }

    mutating func setCurrent(_ track: Track) {
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            currentIndex = index
        } else {
            tracks.append(track)
            currentIndex = tracks.count - 1
        }
    }

    mutating func replaceCurrentTrack(with track: Track) {
        guard let currentIndex, tracks.indices.contains(currentIndex) else {
            setCurrent(track)
            return
        }
        tracks[currentIndex] = track
        removeCurrentTrackDuplicatesFromUpcoming()
    }

    mutating func appendRelatedTracks(_ relatedTracks: [Track], limit: Int = 24) {
        guard !relatedTracks.isEmpty else { return }
        let current = currentTrack
        var seenKeys = Set(tracks.map(\.queueIdentityKey))
        let currentKey = current?.queueIdentityKey
        let uniqueRelated = relatedTracks
            .filter { track in
                guard track.queueIdentityKey != currentKey else { return false }
                return seenKeys.insert(track.queueIdentityKey).inserted
            }
            .prefix(limit)

        tracks.append(contentsOf: uniqueRelated)
        if let current {
            currentIndex = tracks.firstIndex(where: { $0.id == current.id })
        }
        removeCurrentTrackDuplicatesFromUpcoming()
    }

    mutating func replaceUpcomingTracks(with relatedTracks: [Track], limit: Int = 24) {
        guard let currentIndex,
              tracks.indices.contains(currentIndex)
        else {
            if let firstTrack = relatedTracks.first {
                replace(with: Array(relatedTracks.prefix(limit)), startingAt: firstTrack)
            }
            return
        }

        let current = tracks[currentIndex]
        var preservedTracks = Array(tracks.prefix(currentIndex + 1))
        var seenKeys = Set(preservedTracks.map(\.queueIdentityKey))
        let currentKey = current.queueIdentityKey
        let uniqueRelated = relatedTracks
            .filter { track in
                guard track.queueIdentityKey != currentKey else { return false }
                return seenKeys.insert(track.queueIdentityKey).inserted
            }
            .prefix(limit)

        preservedTracks.append(contentsOf: uniqueRelated)
        tracks = preservedTracks
        self.currentIndex = tracks.firstIndex(where: { $0.isSameQueueTrack(as: current) }) ?? currentIndex
        removeCurrentTrackDuplicatesFromUpcoming()
    }

    mutating func nextTrack() -> Track? {
        guard !tracks.isEmpty else { return nil }
        if currentIndex == nil {
            currentIndex = 0
        }
        let previous = currentTrack

        if repeatMode == .one {
            return currentTrack
        }
        if shuffleEnabled, tracks.count > 1 {
            let current = currentIndex ?? 0
            let candidates = tracks.indices.filter { index in
                guard index != current else { return false }
                guard let previous else { return true }
                return !tracks[index].isSameQueueTrack(as: previous)
            }
            if let picked = candidates.randomElement() {
                currentIndex = picked
                return currentTrack
            }
        }
        let nextIndex = (currentIndex ?? -1) + 1
        if tracks.indices.contains(nextIndex) {
            currentIndex = nextIndex
            if let previous, let candidate = currentTrack, candidate.isSameQueueTrack(as: previous) {
                if let distinctIndex = tracks.indices.dropFirst(nextIndex + 1).first(where: { !tracks[$0].isSameQueueTrack(as: previous) }) {
                    currentIndex = distinctIndex
                }
            }
            return currentTrack
        }
        if repeatMode == .all {
            currentIndex = 0
            if let previous, let candidate = currentTrack, candidate.isSameQueueTrack(as: previous) {
                if let distinctIndex = tracks.indices.first(where: { !tracks[$0].isSameQueueTrack(as: previous) }) {
                    currentIndex = distinctIndex
                }
            }
            return currentTrack
        }
        return nil
    }

    mutating func previousTrack() -> Track? {
        guard !tracks.isEmpty else { return nil }
        let previousIndex = (currentIndex ?? 0) - 1
        if tracks.indices.contains(previousIndex) {
            currentIndex = previousIndex
        } else if repeatMode == .all {
            currentIndex = tracks.count - 1
        }
        return currentTrack
    }

    mutating func move(from offsets: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: offsets, toOffset: destination)
        if let current = currentTrack {
            currentIndex = tracks.firstIndex(where: { $0.id == current.id })
        }
    }

    mutating func remove(at offsets: IndexSet) {
        let current = currentTrack
        tracks.remove(atOffsets: offsets)
        currentIndex = current.flatMap { track in tracks.firstIndex(where: { $0.id == track.id }) }
    }

    private mutating func removeCurrentTrackDuplicatesFromUpcoming() {
        guard let currentIndex,
              tracks.indices.contains(currentIndex)
        else { return }

        let current = tracks[currentIndex]
        var cleanedTracks: [Track] = []
        cleanedTracks.reserveCapacity(tracks.count)

        for (index, track) in tracks.enumerated() {
            if index <= currentIndex {
                cleanedTracks.append(track)
                continue
            }
            if track.isSameQueueTrack(as: current) {
                continue
            }
            cleanedTracks.append(track)
        }

        tracks = cleanedTracks
        self.currentIndex = tracks.indices.contains(currentIndex) ? currentIndex : tracks.firstIndex(where: { $0.isSameQueueTrack(as: current) })
    }
}

private extension Track {
    var queueIdentityKey: String {
        let normalizedVideoId = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedVideoId.isEmpty {
            return "video:\(normalizedVideoId)"
        }
        return "id:\(id)"
    }

    func isSameQueueTrack(as other: Track) -> Bool {
        if queueIdentityKey == other.queueIdentityKey {
            return true
        }

        let lhsTitle = title.queueNormalizedText
        let rhsTitle = other.title.queueNormalizedText
        let lhsArtist = artistLine.queueNormalizedText
        let rhsArtist = other.artistLine.queueNormalizedText

        guard !lhsTitle.isEmpty, !lhsArtist.isEmpty else { return false }
        return lhsTitle == rhsTitle && lhsArtist == rhsArtist
    }
}

private extension String {
    var queueNormalizedText: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
