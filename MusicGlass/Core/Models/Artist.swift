import Foundation

struct Artist: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var browseId: String?
    var name: String
    var thumbnails: [Thumbnail]

    init(id: String, browseId: String? = nil, name: String, thumbnails: [Thumbnail] = []) {
        self.id = id
        self.browseId = browseId
        self.name = name
        self.thumbnails = thumbnails
    }

    var bestThumbnailURL: URL? {
        thumbnails.sorted { ($0.width ?? 0) > ($1.width ?? 0) }.first?.url
    }
}

struct ArtistPage: Codable, Hashable, Sendable {
    var artist: Artist
    var topTracks: [Track]
    var albums: [Album]
    var singles: [Album]
}
