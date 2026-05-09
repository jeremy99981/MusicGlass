import Foundation

struct Album: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var browseId: String?
    var title: String
    var artists: [Artist]
    var year: Int?
    var thumbnails: [Thumbnail]
    var tracks: [Track]

    init(
        id: String,
        browseId: String? = nil,
        title: String,
        artists: [Artist] = [],
        year: Int? = nil,
        thumbnails: [Thumbnail] = [],
        tracks: [Track] = []
    ) {
        self.id = id
        self.browseId = browseId
        self.title = title
        self.artists = artists
        self.year = year
        self.thumbnails = thumbnails
        self.tracks = tracks
    }

    var artistLine: String {
        artists.map(\.name).joined(separator: ", ")
    }

    var bestThumbnailURL: URL? {
        thumbnails.sorted(by: { ($0.width ?? 0) > ($1.width ?? 0) }).first?.url
    }
}
