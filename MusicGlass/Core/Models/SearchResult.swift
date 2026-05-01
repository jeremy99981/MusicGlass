import Foundation

enum SearchFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case songs
    case albums
    case artists
    case playlists
    case featuredPlaylists
    case communityPlaylists
    case videos

    static var allCases: [SearchFilter] {
        [.all, .songs, .albums, .artists, .playlists, .videos]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tout"
        case .songs: "Morceaux"
        case .albums: "Albums"
        case .artists: "Artistes"
        case .playlists, .featuredPlaylists, .communityPlaylists: "Playlists"
        case .videos: "Vidéos"
        }
    }

    var innerTubeParams: String? {
        switch self {
        case .all:
            nil
        case .songs:
            "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
        case .videos:
            "EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D"
        case .albums:
            "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"
        case .artists:
            "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
        case .playlists, .featuredPlaylists:
            "EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D"
        case .communityPlaylists:
            "EgeKAQQoAEABagoQAxAEEAoQCRAF"
        }
    }
}

struct SearchResult: Codable, Hashable, Sendable {
    var tracks: [Track]
    var albums: [Album]
    var artists: [Artist]
    var playlists: [Playlist]
    var videos: [Track]

    static let empty = SearchResult(tracks: [], albums: [], artists: [], playlists: [], videos: [])

    var isEmpty: Bool {
        tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty && videos.isEmpty
    }
}
