import Foundation

enum MusicSource: String, Codable, Sendable {
    case youtubeMusic
}

struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let videoId: String
    let title: String
    var artists: [Artist]
    var album: Album?
    var duration: TimeInterval?
    var thumbnails: [Thumbnail]
    var streamURL: URL?
    var explicit: Bool
    var isLiked: Bool
    var source: MusicSource

    init(
        id: String,
        videoId: String,
        title: String,
        artists: [Artist] = [],
        album: Album? = nil,
        duration: TimeInterval? = nil,
        thumbnails: [Thumbnail] = [],
        streamURL: URL? = nil,
        explicit: Bool = false,
        isLiked: Bool = false,
        source: MusicSource = .youtubeMusic
    ) {
        self.id = id
        self.videoId = videoId
        self.title = title
        self.artists = artists
        self.album = album
        self.duration = duration
        self.thumbnails = thumbnails
        self.streamURL = streamURL
        self.explicit = explicit
        self.isLiked = isLiked
        self.source = source
    }

    var artistLine: String {
        let directArtists = artists.map(\.name).joined(separator: ", ")
        if !directArtists.isEmpty {
            return directArtists
        }
        return album?.artistLine ?? ""
    }

    var bestThumbnailURL: URL? {
        thumbnails.max(by: { $0.artworkScore < $1.artworkScore })?.url
    }
}

private extension Thumbnail {
    var artworkScore: Double {
        let width = Double(width ?? 0)
        let height = Double(height ?? 0)
        let area = max(width * height, 1)
        let aspectRatio = height > 0 ? width / height : 1
        let aspectPenalty = abs(aspectRatio - 1) * 1_000_000
        let squareBonus = (0.9 ... 1.12).contains(aspectRatio) ? 8_000_000.0 : 0.0
        return area + squareBonus - aspectPenalty
    }
}

extension Track {
    static let preview = Track(
        id: "preview-track",
        videoId: "FGBhQbmPwH8",
        title: "One More Time",
        artists: [Artist(id: "artist-daft", browseId: nil, name: "Daft Punk")],
        album: Album(id: "album-preview", browseId: nil, title: "Discovery", artists: []),
        duration: 320,
        thumbnails: [Thumbnail(url: URL(string: "https://i.ytimg.com/vi/FGBhQbmPwH8/hqdefault.jpg")!, width: 480, height: 360)]
    )
}
