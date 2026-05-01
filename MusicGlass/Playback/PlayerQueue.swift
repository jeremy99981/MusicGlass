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
    }

    mutating func appendRelatedTracks(_ relatedTracks: [Track], limit: Int = 24) {
        guard !relatedTracks.isEmpty else { return }
        let current = currentTrack
        var seenIds = Set(tracks.map(\.id))
        let uniqueRelated = relatedTracks
            .filter { track in
                guard track.id != current?.id else { return false }
                return seenIds.insert(track.id).inserted
            }
            .prefix(limit)

        tracks.append(contentsOf: uniqueRelated)
        if let current {
            currentIndex = tracks.firstIndex(where: { $0.id == current.id })
        }
    }

    mutating func nextTrack() -> Track? {
        guard !tracks.isEmpty else { return nil }
        if repeatMode == .one {
            return currentTrack
        }
        if shuffleEnabled, tracks.count > 1 {
            let current = currentIndex ?? 0
            let candidates = tracks.indices.filter { $0 != current }
            currentIndex = candidates.randomElement()
            return currentTrack
        }
        let nextIndex = (currentIndex ?? -1) + 1
        if tracks.indices.contains(nextIndex) {
            currentIndex = nextIndex
            return currentTrack
        }
        if repeatMode == .all {
            currentIndex = 0
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
}
