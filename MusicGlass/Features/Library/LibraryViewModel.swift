import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var favorites: [Track] = []
    @Published private(set) var history: [Track] = []
    @Published private(set) var playlists: [StoredPlaylistRecord] = []
    @Published private(set) var ytLikedSongs: [Track] = []
    @Published private(set) var ytPlaylists: [Playlist] = []
    @Published private(set) var ytHistory: [Track] = []
    @Published private(set) var isLoadingYTLibrary = false
    @Published var errorMessage: String?

    private let favoritesRepository: FavoriteRepository
    private let historyRepository: HistoryRepository
    private let playlistRepository: PlaylistRepository
    private let youTubeMusicClient: YouTubeMusicClientProtocol
    private let authService: AuthService

    init(
        favoritesRepository: FavoriteRepository,
        historyRepository: HistoryRepository,
        playlistRepository: PlaylistRepository,
        youTubeMusicClient: YouTubeMusicClientProtocol,
        authService: AuthService
    ) {
        self.favoritesRepository = favoritesRepository
        self.historyRepository = historyRepository
        self.playlistRepository = playlistRepository
        self.youTubeMusicClient = youTubeMusicClient
        self.authService = authService
    }

    func load() {
        do {
            favorites = try favoritesRepository.allFavorites()
            history = try historyRepository.recentlyPlayed()
            playlists = try playlistRepository.localPlaylists()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        // Load YouTube Music library if authenticated
        if authService.isAuthenticated {
            loadYTLibrary()
        } else {
            ytLikedSongs = []
            ytPlaylists = []
            ytHistory = []
            AppLogger.youtube.notice("Not authenticated, skipping YT library load")
        }
    }

    func clearHistory() {
        do {
            try historyRepository.clear()
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadYTLibrary() {
        guard !isLoadingYTLibrary else { return }
        isLoadingYTLibrary = true

        Task {
            // Fetch each independently so one failure doesn't block others
            var liked: [Track] = []
            var userPlaylists: [Playlist] = []
            var ytHist: [Track] = []
            var authFailureCount = 0

            do {
                liked = try await youTubeMusicClient.getLikedSongs()
                AppLogger.youtube.notice("YT Liked songs: \(liked.count)")
            } catch {
                if error.isUnauthorizedResponse { authFailureCount += 1 }
                AppLogger.youtube.error("Failed to load YT liked songs: \(error.localizedDescription, privacy: .public)")
            }

            do {
                userPlaylists = try await youTubeMusicClient.getUserPlaylists()
                AppLogger.youtube.notice("YT Playlists: \(userPlaylists.count)")
            } catch {
                if error.isUnauthorizedResponse { authFailureCount += 1 }
                AppLogger.youtube.error("Failed to load YT playlists: \(error.localizedDescription, privacy: .public)")
            }

            do {
                ytHist = try await youTubeMusicClient.getYTHistory()
                AppLogger.youtube.notice("YT History: \(ytHist.count)")
            } catch {
                if error.isUnauthorizedResponse { authFailureCount += 1 }
                AppLogger.youtube.error("Failed to load YT history: \(error.localizedDescription, privacy: .public)")
            }

            if authFailureCount >= 3 {
                AppLogger.youtube.warning("YT Library auth rejected by YouTube Music, clearing stored session")
                authService.clear()
            }

            self.ytLikedSongs = liked
            self.ytPlaylists = userPlaylists
            self.ytHistory = ytHist
            self.isLoadingYTLibrary = false

            AppLogger.youtube.notice("YT Library loaded: \(liked.count) likes, \(userPlaylists.count) playlists, \(ytHist.count) history")
        }
    }

    /// Combined favorites: local + YouTube Music liked songs
    var allFavorites: [Track] {
        let localIds = Set(favorites.map(\.id))
        let uniqueYTLikes = ytLikedSongs.filter { !localIds.contains($0.id) }
        return favorites + uniqueYTLikes
    }

    /// Combined history: local + YouTube Music history
    var allHistory: [Track] {
        let localIds = Set(history.map(\.id))
        let uniqueYTHistory = ytHistory.filter { !localIds.contains($0.id) }
        return history + uniqueYTHistory
    }
}

private extension Error {
    var isUnauthorizedResponse: Bool {
        guard let networkError = self as? NetworkError else { return false }
        if case .httpStatus(let status, _) = networkError {
            return status == 401 || status == 403
        }
        return false
    }
}
