import Foundation

struct HomeFeed: Codable, Hashable, Sendable {
    var sections: [HomeSection]

    static let empty = HomeFeed(sections: [])
}

struct HomeSection: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var items: [HomeItem]
}

enum HomeItem: Identifiable, Codable, Hashable, Sendable {
    case track(Track)
    case album(Album)
    case artist(Artist)
    case playlist(Playlist)

    var id: String {
        switch self {
        case .track(let track): "track-\(track.id)"
        case .album(let album): "album-\(album.id)"
        case .artist(let artist): "artist-\(artist.id)"
        case .playlist(let playlist): "playlist-\(playlist.id)"
        }
    }

    var title: String {
        switch self {
        case .track(let track): track.title
        case .album(let album): album.title
        case .artist(let artist): artist.name
        case .playlist(let playlist): playlist.title
        }
    }

    var subtitle: String {
        switch self {
        case .track(let track): track.artistLine
        case .album(let album): album.artistLine
        case .artist: "Artiste"
        case .playlist(let playlist): playlist.author ?? "Playlist"
        }
    }

    var artworkURL: URL? {
        switch self {
        case .track(let track): track.bestThumbnailURL
        case .album(let album): album.bestThumbnailURL
        case .artist(let artist): artist.bestThumbnailURL
        case .playlist(let playlist): playlist.bestThumbnailURL
        }
    }
}
