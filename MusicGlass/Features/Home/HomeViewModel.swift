import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var feed: HomeFeed = .empty
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private(set) var hasLoadedBaseFeed = false

    private let client: YouTubeMusicClientProtocol
    private let historyRepository: HistoryRepository
    private let authService: AuthService

    init(client: YouTubeMusicClientProtocol, historyRepository: HistoryRepository, authService: AuthService) {
        self.client = client
        self.historyRepository = historyRepository
        self.authService = authService
    }

    func loadIfNeeded() {
        guard !hasLoadedBaseFeed else { return }
        load()
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            let history = (try? historyRepository.recentlyPlayed()) ?? []
            async let baseFeedTask: HomeFeed? = try? await client.getHome()
            async let discoverySectionsTask = makeDiscoverySections(from: history)
            async let userPlaylistsTask: [Playlist] = authService.isAuthenticated ? ((try? await client.getUserPlaylists()) ?? []) : []

            let baseFeed = await baseFeedTask ?? .empty
            let userPlaylists = await userPlaylistsTask
            let firstFeed = buildFeed(baseFeed: baseFeed, history: history, discoverySections: [], userPlaylists: userPlaylists)
            if !firstFeed.sections.isEmpty {
                self.feed = firstFeed
            }

            let discoverySections = await discoverySectionsTask
            let finalFeed = buildFeed(baseFeed: baseFeed, history: history, discoverySections: discoverySections, userPlaylists: userPlaylists)
            self.feed = finalFeed
            self.hasLoadedBaseFeed = true
#if DEBUG
            logLoadedSections(finalFeed)
#endif

            if finalFeed.sections.isEmpty {
                self.errorMessage = "Impossible de charger les recommandations pour le moment."
            }
            self.isLoading = false
        }
    }

    func refreshRecentlyPlayedSection() {
        let history = ((try? historyRepository.recentlyPlayed()) ?? [])
            .filter(\.musicGlassIsHomeTrack)
        var sections = feed.sections.filter { $0.id != "recently-played" }

        if !history.isEmpty {
            let recentlyPlayed = HomeSection(
                id: "recently-played",
                title: "Écoutés récemment",
                items: history.prefix(12).map(HomeItem.track)
            )
            sections.insert(recentlyPlayed, at: 0)
        }

        feed = HomeFeed(sections: sections)
    }

    private func buildFeed(baseFeed: HomeFeed, history: [Track], discoverySections: [HomeSection], userPlaylists: [Playlist]) -> HomeFeed {
        var sections: [HomeSection] = []

        let cleanHistory = history.filter(\.musicGlassIsHomeTrack)
        if !cleanHistory.isEmpty {
            sections.append(
                HomeSection(
                    id: "recently-played",
                    title: "Écoutés récemment",
                    items: cleanHistory.prefix(12).map(HomeItem.track)
                )
            )
        }

        // Add user's YouTube Music playlists
        if !userPlaylists.isEmpty {
            sections.append(
                HomeSection(
                    id: "user-playlists",
                    title: "Mes playlists",
                    items: userPlaylists.prefix(16).map(HomeItem.playlist)
                )
            )
        }

        sections.append(contentsOf: discoverySections)
        sections.append(contentsOf: splitPlaylistSections(baseFeed.sections))

        return HomeFeed(sections: sanitizeSections(sections))
    }

#if DEBUG
    private func logLoadedSections(_ feed: HomeFeed) {
        let summary = feed.sections
            .map { section in
                let itemTitles = section.items.prefix(4).map(\.title).joined(separator: ", ")
                return "\(section.title) [\(section.items.count)]: \(itemTitles)"
            }
            .joined(separator: " | ")
        AppLogger.youtube.debug("Home sections loaded: \(summary, privacy: .public)")
    }
#endif

    private func makeDiscoverySections(from history: [Track]) async -> [HomeSection] {
        let queries = discoveryQueries(from: history)
        guard !queries.isEmpty else { return [] }

        let client = self.client
        return await withTaskGroup(of: HomeSection?.self) { group in
            for query in queries {
                group.addTask {
                    do {
                        var items: [HomeItem] = []
                        for searchQuery in query.searchQueries {
                            let result = try await client.search(query: searchQuery, filter: query.filter)
                            items.append(contentsOf: query.items(from: result))
                            if items.uniquedBy(\.id).count >= query.limit {
                                break
                            }
                        }
                        items = items.uniquedBy(\.id)
                        guard !items.isEmpty else { return nil }
                        return HomeSection(id: query.id, title: query.title, items: Array(items.prefix(query.limit)))
                    } catch {
                        return nil
                    }
                }
            }

            var sections: [HomeSection] = []
            for await section in group {
                if let section {
                    sections.append(section)
                }
            }

            let order = Dictionary(uniqueKeysWithValues: queries.enumerated().map { ($0.element.id, $0.offset) })
            return sections.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
        }
    }

    private nonisolated func discoveryQueries(from history: [Track]) -> [HomeDiscoveryQuery] {
        var queries: [HomeDiscoveryQuery] = [
            HomeDiscoveryQuery(id: "trending-tracks", title: "Titres tendance", query: "titres tendance France", fallbackQueries: ["hits du moment France", "top titres France", "nouveautés rap pop France"], filter: .songs, content: .tracks, limit: 16),
            HomeDiscoveryQuery(id: "official-playlists", title: "Playlists officielles", query: "France hits", fallbackQueries: ["Rap Français Hits YouTube Music", "Hits 80 YouTube Music", "Hits 90 YouTube Music", "Pop Hits YouTube Music", "Nouveautés YouTube Music"], filter: .featuredPlaylists, content: .officialPlaylists, limit: 16),
            HomeDiscoveryQuery(id: "popular-albums", title: "Albums tendance", query: "albums tendance France", fallbackQueries: ["albums rap français 2026", "albums pop française 2026", "nouveaux albums France"], filter: .albums, content: .albums, limit: 14),
            HomeDiscoveryQuery(id: "new-releases", title: "Nouveautés à découvrir", query: "nouveautés musique France", fallbackQueries: ["nouveautés rap français", "nouveautés pop française", "sorties musique France"], filter: .songs, content: .tracks, limit: 16),
            HomeDiscoveryQuery(id: "community-playlists", title: "Playlists communautaires", query: "France hits", fallbackQueries: ["playlist rap français", "playlist pop française", "playlist soirée France", "playlist chill français"], filter: .communityPlaylists, content: .communityPlaylists, limit: 16),
            HomeDiscoveryQuery(id: "rap-tracks", title: "Rap français du moment", query: "rap français nouveautés", filter: .songs, content: .tracks, limit: 16),
            HomeDiscoveryQuery(id: "pop-tracks", title: "Pop française", query: "pop française nouveautés", filter: .songs, content: .tracks, limit: 14),
            HomeDiscoveryQuery(id: "official-chill", title: "Officiel - pour se poser", query: "chill détente", fallbackQueries: ["Relax YouTube Music", "Chill Hits YouTube Music", "Acoustic Chill YouTube Music"], filter: .featuredPlaylists, content: .officialPlaylists, limit: 12),
            HomeDiscoveryQuery(id: "community-chill", title: "Communauté - pour se poser", query: "chill détente", fallbackQueries: ["playlist chill détente", "playlist calme français", "playlist détente musique"], filter: .communityPlaylists, content: .communityPlaylists, limit: 12),
            HomeDiscoveryQuery(id: "weekend-energy", title: "Énergie week-end", query: "hits énergie week-end", filter: .songs, content: .tracks, limit: 14)
        ]

        let artistNames = topArtistNames(from: history, limit: 3)
        for artist in artistNames {
            let safeId = artist.musicGlassStableSectionId
            queries.append(
                HomeDiscoveryQuery(
                    id: "artist-\(safeId)-tracks",
                    title: "Plus de \(artist)",
                    query: "\(artist) meilleurs titres",
                    filter: .songs,
                    content: .tracks,
                    limit: 12
                )
            )
            queries.append(
                HomeDiscoveryQuery(
                    id: "artist-\(safeId)-mixes",
                    title: "Dans l’univers de \(artist)",
                    query: "\(artist) radio artistes similaires",
                    filter: .songs,
                    content: .tracks,
                    limit: 12
                )
            )
        }

        for theme in inferredThemes(from: history).prefix(4) {
            queries.append(
                HomeDiscoveryQuery(
                    id: "theme-\(theme.id)",
                    title: theme.title,
                    query: theme.query,
                    filter: .songs,
                    content: .tracks,
                    limit: 14
                )
            )
        }

        return queries.uniquedBy(\.id)
    }

    private nonisolated func topArtistNames(from history: [Track], limit: Int) -> [String] {
        let counts = history
            .flatMap { track -> [String] in
                if !track.artists.isEmpty {
                    return track.artists.map(\.name)
                }
                return track.artistLine
                    .components(separatedBy: CharacterSet(charactersIn: ",&"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("unknown") }
            .reduce(into: [String: Int]()) { counts, artist in
                counts[artist, default: 0] += 1
            }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
                } else {
                    lhs.value > rhs.value
                }
            }
            .prefix(limit)
            .map(\.key)
    }

    private nonisolated func inferredThemes(from history: [Track]) -> [HomeTheme] {
        let listeningText = history
            .flatMap { [$0.title, $0.artistLine, $0.album?.title ?? ""] }
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let themes: [HomeThemeMatcher] = [
            HomeThemeMatcher(
                theme: HomeTheme(id: "rap-fr", title: "Rap français pour vous", query: "rap français nouveautés"),
                keywords: ["plk", "ninho", "pnl", "jul", "damso", "nekfeu", "laylow", "tiakola", "gazo", "zola", "niska", "koba", "hamza", "leto", "sdm", "freeze corleone", "rap"]
            ),
            HomeThemeMatcher(
                theme: HomeTheme(id: "pop-fr", title: "Pop française à explorer", query: "pop française nouveautés"),
                keywords: ["angele", "stromae", "clara luciani", "zaho de sagazan", "helene sio", "pomme", "louane", "vianney", "pop"]
            ),
            HomeThemeMatcher(
                theme: HomeTheme(id: "rnb", title: "R&B et vibes douces", query: "rnb francais chill"),
                keywords: ["rnb", "r&b", "the weeknd", "sza", "frank ocean", "soul", "hamza", "tsew the kid"]
            ),
            HomeThemeMatcher(
                theme: HomeTheme(id: "electro", title: "Électro et énergie", query: "electro house nouveautés"),
                keywords: ["electro", "house", "techno", "daft punk", "justice", "kavinsky", "gesaffelstein", "dance"]
            ),
            HomeThemeMatcher(
                theme: HomeTheme(id: "rock-alt", title: "Rock et alternatif", query: "rock alternatif nouveautés"),
                keywords: ["rock", "twenty one pilots", "arctic monkeys", "tame impala", "coldplay", "indie", "alternative"]
            ),
            HomeThemeMatcher(
                theme: HomeTheme(id: "focus", title: "Concentration et calme", query: "concentration chill lo-fi"),
                keywords: ["lofi", "lo-fi", "chill", "focus", "piano", "study", "sleep", "calme"]
            )
        ]

        let matched = themes
            .filter { matcher in matcher.keywords.contains { listeningText.contains($0) } }
            .map(\.theme)

        if matched.isEmpty, !history.isEmpty {
            let seedArtists = history.prefix(3)
                .map(\.artistLine)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return [
                HomeTheme(id: "personal-radio", title: "Inspiré par vos écoutes", query: "\(seedArtists) radio")
            ]
        }

        return matched
    }

    private nonisolated func sanitizeSections(_ sections: [HomeSection]) -> [HomeSection] {
        var seenSectionIds = Set<String>()
        var seenItemIds = Set<String>()

        return sections.compactMap { section in
            guard seenSectionIds.insert(section.id).inserted else { return nil }
            let items = section.items
                .filter(\.musicGlassIsAllowedOnHome)
                .filter { item in seenItemIds.insert(item.id).inserted }
            guard !items.isEmpty else { return nil }
            return HomeSection(id: section.id, title: section.title, items: items)
        }
    }

    private nonisolated func splitPlaylistSections(_ sections: [HomeSection]) -> [HomeSection] {
        sections.flatMap { section -> [HomeSection] in
            let nonPlaylistItems = section.items.filter { item in
                if case .playlist = item { return false }
                return item.musicGlassIsAllowedOnHome
            }
            let officialPlaylistItems = section.items.filter { item in
                if case .playlist(let playlist) = item {
                    return playlist.musicGlassIsHomePlaylist && playlist.musicGlassIsOfficialYouTubeMusic
                }
                return false
            }
            let communityPlaylistItems = section.items.filter { item in
                if case .playlist(let playlist) = item {
                    return playlist.musicGlassIsHomePlaylist && !playlist.musicGlassIsOfficialYouTubeMusic
                }
                return false
            }

            var splitSections: [HomeSection] = []
            if !nonPlaylistItems.isEmpty {
                splitSections.append(HomeSection(id: section.id, title: section.title, items: nonPlaylistItems))
            }
            if !officialPlaylistItems.isEmpty {
                splitSections.append(HomeSection(id: "\(section.id)-official", title: "\(section.title) - officiel", items: officialPlaylistItems))
            }
            if !communityPlaylistItems.isEmpty {
                splitSections.append(HomeSection(id: "\(section.id)-community", title: "\(section.title) - communauté", items: communityPlaylistItems))
            }
            return splitSections
        }
    }
}

private struct HomeDiscoveryQuery: Sendable, Hashable {
    enum Content: Sendable, Hashable {
        case tracks
        case officialPlaylists
        case communityPlaylists
        case albums
    }

    var id: String
    var title: String
    var query: String
    var fallbackQueries: [String] = []
    var filter: SearchFilter?
    var content: Content
    var limit: Int

    var searchQueries: [String] {
        ([query] + fallbackQueries).uniqued()
    }

    func items(from result: SearchResult) -> [HomeItem] {
        switch content {
        case .tracks:
            return result.tracks
                .filter(\.musicGlassIsHomeTrack)
                .map(HomeItem.track)
        case .officialPlaylists:
            return result.playlists
                .filter(\.musicGlassIsHomePlaylist)
                .filter(\.musicGlassIsOfficialYouTubeMusic)
                .map(HomeItem.playlist)
        case .communityPlaylists:
            return result.playlists
                .filter(\.musicGlassIsHomePlaylist)
                .filter { !$0.musicGlassIsOfficialYouTubeMusic }
                .map(HomeItem.playlist)
        case .albums:
            return result.albums
                .filter(\.musicGlassIsHomeAlbum)
                .map(HomeItem.album)
        }
    }
}

private struct HomeTheme: Sendable, Hashable {
    var id: String
    var title: String
    var query: String
}

private struct HomeThemeMatcher: Sendable, Hashable {
    var theme: HomeTheme
    var keywords: [String]
}

private extension String {
    var musicGlassStableSectionId: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

private extension HomeItem {
    var musicGlassIsAllowedOnHome: Bool {
        switch self {
        case .track(let track):
            track.musicGlassIsHomeTrack
        case .album(let album):
            album.musicGlassIsHomeAlbum
        case .playlist(let playlist):
            playlist.musicGlassIsHomePlaylist
        case .artist:
            false
        }
    }
}

private extension Track {
    var musicGlassIsHomeTrack: Bool {
        let folded = ([title, artistLine, album?.title ?? ""]).joined(separator: " ").musicGlassFolded
        guard !folded.musicGlassHasBlockedMusicSignal else { return false }
        guard !folded.musicGlassLooksLikeLongFormMusicCard else { return false }
        guard !artistLine.musicGlassFolded.isEmpty else { return false }
        if let duration {
            return duration >= 25 && duration <= 12 * 60
        }
        return false
    }
}

private extension Album {
    var musicGlassIsHomeAlbum: Bool {
        let folded = ([title, artistLine]).joined(separator: " ").musicGlassFolded
        return !folded.musicGlassHasBlockedMusicSignal && !folded.musicGlassLooksLikeLongFormMusicCard
    }
}

private extension Playlist {
    var musicGlassIsHomePlaylist: Bool {
        let folded = ([title, author ?? "", description ?? ""]).joined(separator: " ").musicGlassFolded
        return !folded.musicGlassHasBlockedMusicSignal && !folded.musicGlassLooksLikePlaylistPollution
    }

    var musicGlassIsOfficialYouTubeMusic: Bool {
        let author = (author ?? "").musicGlassFolded
        let title = title.musicGlassFolded
        let officialAuthors = ["youtube music", "youtube", "yt music", "charts"]
        if officialAuthors.contains(where: { author == $0 || author.contains($0) }) {
            return true
        }

        let officialTitleHints = [
            "hits du",
            "hits de",
            "les hits",
            "top 100",
            "top france",
            "nouveautes",
            "decouvertes",
            "tendances",
            "charts"
        ]
        return author.isEmpty && officialTitleHints.contains { title.contains($0) }
    }
}

private extension String {
    var musicGlassFolded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var musicGlassHasBlockedMusicSignal: Bool {
        contains("podcast") ||
            contains("episode") ||
            contains("audiobook") ||
            contains("livre audio") ||
            contains("interview") ||
            contains("documentaire") ||
            contains("documentary") ||
            contains("reaction") ||
            contains("talk show") ||
            contains("news")
    }

    var musicGlassLooksLikeLongFormMusicCard: Bool {
        contains("1 hour") ||
            contains("2 hour") ||
            contains("3 hour") ||
            contains("1h") ||
            contains("2h") ||
            contains("3h") ||
            contains("heure") ||
            contains("full album") ||
            contains("album complet") ||
            contains("compilation") ||
            contains("megamix") ||
            contains("mega mix") ||
            contains("non stop") ||
            contains("24/7") ||
            contains("top 100") ||
            contains("top 50") ||
            contains("best of")
    }

    var musicGlassLooksLikePlaylistPollution: Bool {
        contains("1 hour") ||
            contains("2 hour") ||
            contains("3 hour") ||
            contains("1h") ||
            contains("2h") ||
            contains("3h") ||
            contains("heure") ||
            contains("mix 202") ||
            contains("podcast") ||
            contains("episode") ||
            contains("video mix") ||
            contains("clips") ||
            contains("clip officiel") ||
            contains("karaoke") ||
            contains("live stream") ||
            contains("24/7")
    }
}
