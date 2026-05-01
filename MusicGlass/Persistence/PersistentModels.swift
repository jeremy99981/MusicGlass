import Foundation
import SwiftData

enum StoredTrackKind: String, Codable {
    case favorite
    case history
    case savedAlbum
    case savedArtist
}

@Model
final class StoredTrackRecord {
    @Attribute(.unique) var id: String
    var kindRaw: String
    var trackId: String
    var videoId: String
    var title: String
    var artistLine: String
    var albumTitle: String?
    var duration: TimeInterval?
    var thumbnailURLString: String?
    var playCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(kind: StoredTrackKind, track: Track, date: Date = Date()) {
        self.id = "\(kind.rawValue)-\(track.id)"
        self.kindRaw = kind.rawValue
        self.trackId = track.id
        self.videoId = track.videoId
        self.title = track.title
        self.artistLine = track.artistLine
        self.albumTitle = track.album?.title
        self.duration = track.duration
        self.thumbnailURLString = track.bestThumbnailURL?.absoluteString
        self.playCount = kind == .history ? 1 : 0
        self.createdAt = date
        self.updatedAt = date
    }

    var kind: StoredTrackKind {
        StoredTrackKind(rawValue: kindRaw) ?? .history
    }

    func update(from track: Track, date: Date = Date(), incrementPlayCount: Bool = false) {
        trackId = track.id
        videoId = track.videoId
        title = track.title
        artistLine = track.artistLine
        albumTitle = track.album?.title
        duration = track.duration
        thumbnailURLString = track.bestThumbnailURL?.absoluteString
        updatedAt = date
        if incrementPlayCount {
            playCount += 1
        }
    }

    func toTrack(isLiked: Bool = false) -> Track {
        let artists = artistLine
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Artist(id: $0.lowercased(), name: $0) }
        let thumbnails = thumbnailURLString.flatMap(URL.init(string:)).map { [Thumbnail(url: $0, width: nil, height: nil)] } ?? []
        let album = albumTitle.map { Album(id: $0.lowercased(), title: $0) }
        return Track(
            id: trackId,
            videoId: videoId,
            title: title,
            artists: artists,
            album: album,
            duration: duration,
            thumbnails: thumbnails,
            isLiked: isLiked
        )
    }
}

@Model
final class StoredPlaylistRecord {
    @Attribute(.unique) var id: String
    var title: String
    var trackIds: [String]
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, title: String, trackIds: [String] = []) {
        self.id = id
        self.title = title
        self.trackIds = trackIds
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class StoredCacheRecord {
    @Attribute(.unique) var id: String
    var byteCount: Int
    var kind: String
    var updatedAt: Date

    init(id: String, byteCount: Int, kind: String) {
        self.id = id
        self.byteCount = byteCount
        self.kind = kind
        self.updatedAt = Date()
    }
}
