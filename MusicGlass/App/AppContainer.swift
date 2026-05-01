import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let httpClient: HTTPClientProtocol
    let innerTubeClient: InnerTubeClient
    let youTubeMusicClient: YouTubeMusicClientProtocol
    let lyricsService: LyricsServiceProtocol
    let localDatabase: LocalDatabase
    let favoritesRepository: FavoriteRepository
    let historyRepository: HistoryRepository
    let playlistRepository: PlaylistRepository
    let cacheRepository: CacheRepository
    let playbackCacheManager: PlaybackCacheManager
    let authService: AuthService
    let playerEngine: AVPlayerEngine

    private init(
        httpClient: HTTPClientProtocol,
        innerTubeClient: InnerTubeClient,
        youTubeMusicClient: YouTubeMusicClientProtocol,
        lyricsService: LyricsServiceProtocol,
        localDatabase: LocalDatabase,
        favoritesRepository: FavoriteRepository,
        historyRepository: HistoryRepository,
        playlistRepository: PlaylistRepository,
        cacheRepository: CacheRepository,
        playbackCacheManager: PlaybackCacheManager,
        authService: AuthService,
        playerEngine: AVPlayerEngine
    ) {
        self.httpClient = httpClient
        self.innerTubeClient = innerTubeClient
        self.youTubeMusicClient = youTubeMusicClient
        self.lyricsService = lyricsService
        self.localDatabase = localDatabase
        self.favoritesRepository = favoritesRepository
        self.historyRepository = historyRepository
        self.playlistRepository = playlistRepository
        self.cacheRepository = cacheRepository
        self.playbackCacheManager = playbackCacheManager
        self.authService = authService
        self.playerEngine = playerEngine
    }

    static func live() -> AppContainer {
        let authService = AuthService()
        let logger = NetworkLogger()
        let httpClient = HTTPClient(logger: logger)
        let innerTubeClient = InnerTubeClient(httpClient: httpClient, authService: authService)
        let mapper = InnerTubeJSONMapper()
        let lyricsService = LRCLibLyricsService(httpClient: httpClient)
        let youTubeMusicClient = YouTubeMusicClient(
            innerTubeClient: innerTubeClient,
            mapper: mapper,
            lyricsService: lyricsService
        )
        let localDatabase = LocalDatabase.live()
        let favoritesRepository = FavoriteRepository(database: localDatabase)
        let historyRepository = HistoryRepository(database: localDatabase)
        let playlistRepository = PlaylistRepository(database: localDatabase)
        let cacheRepository = CacheRepository(database: localDatabase)
        let playbackCacheManager = PlaybackCacheManager()
        let nowPlayingManager = NowPlayingManager()
        let remoteCommandCenterManager = RemoteCommandCenterManager()
        let audioSessionManager = AudioSessionManager()
        let playerEngine = AVPlayerEngine(
            youTubeMusicClient: youTubeMusicClient,
            historyRepository: historyRepository,
            nowPlayingManager: nowPlayingManager,
            remoteCommandCenterManager: remoteCommandCenterManager,
            audioSessionManager: audioSessionManager
        )

#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let videoId = environment["MUSICGLASS_DEBUG_AUTOPLAY_VIDEO_ID"],
           !videoId.isEmpty {
            let title = environment["MUSICGLASS_DEBUG_AUTOPLAY_TITLE"] ?? "Debug Track"
            let artistName = environment["MUSICGLASS_DEBUG_AUTOPLAY_ARTIST"]
            let artists = artistName.map { [Artist(id: $0.lowercased(), name: $0)] } ?? []
            let track = Track(id: videoId, videoId: videoId, title: title, artists: artists)
            Task { @MainActor in
                playerEngine.play(track, queue: [track])
            }
            if let pauseDelay = environment["MUSICGLASS_DEBUG_AUTOPAUSE_AFTER_SECONDS"].flatMap(TimeInterval.init),
               pauseDelay > 0 {
                Task { @MainActor in
                    let deadline = Date().addingTimeInterval(max(30, pauseDelay + 20))
                    while Date() < deadline, playerEngine.progress < 2, playerEngine.state != .playing {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(pauseDelay * 1_000_000_000))
                    playerEngine.pause()
                }
            }
        }
#endif

        return AppContainer(
            httpClient: httpClient,
            innerTubeClient: innerTubeClient,
            youTubeMusicClient: youTubeMusicClient,
            lyricsService: lyricsService,
            localDatabase: localDatabase,
            favoritesRepository: favoritesRepository,
            historyRepository: historyRepository,
            playlistRepository: playlistRepository,
            cacheRepository: cacheRepository,
            playbackCacheManager: playbackCacheManager,
            authService: authService,
            playerEngine: playerEngine
        )
    }
}
