import Foundation

enum AppTab: Hashable {
    case home
    case search
    case library
}

enum PlayerSheet: Identifiable {
    case fullPlayer
    case queue
    case lyrics(Track)

    var id: String {
        switch self {
        case .fullPlayer:
            "fullPlayer"
        case .queue:
            "queue"
        case .lyrics(let track):
            "lyrics-\(track.id)"
        }
    }
}

enum MusicDestination: Hashable {
    case album(String)
    case artist(String)
    case playlist(String)
    case libraryArtists
    case libraryArtist(String)
}
