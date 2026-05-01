import Foundation

struct Playlist: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var browseId: String?
    var title: String
    var author: String?
    var description: String?
    var thumbnails: [Thumbnail]
    var tracks: [Track]
    var trackCount: Int?

    init(
        id: String,
        browseId: String? = nil,
        title: String,
        author: String? = nil,
        description: String? = nil,
        thumbnails: [Thumbnail] = [],
        tracks: [Track] = [],
        trackCount: Int? = nil
    ) {
        self.id = id
        self.browseId = browseId
        self.title = title
        self.author = author
        self.description = description
        self.thumbnails = thumbnails
        self.tracks = tracks
        self.trackCount = trackCount
    }

    var bestThumbnailURL: URL? {
        thumbnails.sorted { ($0.width ?? 0) > ($1.width ?? 0) }.first?.url
    }
}
