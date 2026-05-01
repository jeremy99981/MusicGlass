import Foundation

enum PlayerState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case failed(String)

    var isActive: Bool {
        switch self {
        case .playing, .paused, .buffering:
            true
        case .idle, .loading, .failed:
            false
        }
    }
}
