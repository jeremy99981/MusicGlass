import Foundation

protocol YouTubeMusicClientProtocol: Sendable {
    func search(query: String, filter: SearchFilter?) async throws -> SearchResult
    func getHome() async throws -> HomeFeed
    func getAlbum(browseId: String) async throws -> Album
    func getArtist(browseId: String) async throws -> ArtistPage
    func getPlaylist(browseId: String) async throws -> Playlist
    func enrichArtwork(for tracks: [Track], fallbackAlbum: Album?, limit: Int) async -> [Track]
    func getPlayer(videoId: String) async throws -> PlayerPayload
    func resolveStreamUrl(videoId: String) async throws -> URL
    func getRelatedTracks(videoId: String) async throws -> [Track]
    func getLyrics(videoId: String, metadata: Track) async throws -> Lyrics?
    func getSuggestions(query: String) async throws -> [String]
    func getLikedSongs() async throws -> [Track]
    func getUserPlaylists() async throws -> [Playlist]
    func getYTHistory() async throws -> [Track]
    func setLike(videoId: String, liked: Bool) async throws
}

struct YouTubeMusicClient: YouTubeMusicClientProtocol {
    private let innerTubeClient: InnerTubeClient
    private let mapper: InnerTubeJSONMapper
    private let lyricsService: LyricsServiceProtocol
    private static let artworkCache = ArtworkEnrichmentCache()

    init(
        innerTubeClient: InnerTubeClient,
        mapper: InnerTubeJSONMapper,
        lyricsService: LyricsServiceProtocol
    ) {
        self.innerTubeClient = innerTubeClient
        self.mapper = mapper
        self.lyricsService = lyricsService
    }

    func search(query: String, filter: SearchFilter?) async throws -> SearchResult {
        let value = try await innerTubeClient.search(query: query, filter: filter)
        let result = mapper.mapSearchResult(from: value)
        guard !result.isEmpty else {
            return .empty
        }
        return applyLocalFilter(sanitize(result), filter: filter)
    }

    func getHome() async throws -> HomeFeed {
        let value = try await innerTubeClient.browse(browseId: "FEmusic_home")
        let feed = mapper.mapHomeFeed(from: value)
        if feed.sections.isEmpty {
            return HomeFeed(sections: [HomeSection(id: "quick-picks-empty", title: "Suggestions rapides", items: [])])
        }
        return feed
    }

    func getAlbum(browseId: String) async throws -> Album {
        let value = try await innerTubeClient.browse(browseId: browseId)
        return mapper.mapAlbum(from: value, browseId: browseId)
    }

    func getArtist(browseId: String) async throws -> ArtistPage {
        let value = try await innerTubeClient.browse(browseId: browseId)
        return mapper.mapArtistPage(from: value, browseId: browseId)
    }

    func getPlaylist(browseId: String) async throws -> Playlist {
        let value = try await innerTubeClient.browse(browseId: browseId)
        var playlist = mapper.mapPlaylist(from: value, browseId: browseId)
        if playlist.tracks.isEmpty, let playlistId = browseId.musicGlassPlainPlaylistId,
           let queueValue = try? await innerTubeClient.playlistQueue(playlistId: playlistId) {
            let tracks = mapper.mapNextTracks(from: queueValue)
                .filter(\.musicGlassIsLikelyMusicTrack)
                .uniquedBy(\.id)
            if !tracks.isEmpty {
                playlist.tracks = tracks
                playlist.trackCount = tracks.count
            }
        }
        playlist.trackCount = playlist.tracks.count
        return playlist
    }

    func enrichArtwork(for tracks: [Track], fallbackAlbum: Album?, limit: Int) async -> [Track] {
        await artworkEnrichedTracks(tracks, fallbackAlbum: fallbackAlbum, limit: limit)
    }

    func getPlayer(videoId: String) async throws -> PlayerPayload {
        let value = try await innerTubeClient.player(videoId: videoId)
        return mapper.mapPlayerPayload(from: value, videoId: videoId)
    }

    func resolveStreamUrl(videoId: String) async throws -> URL {
        let payload = try await getPlayer(videoId: videoId)
        guard payload.playabilityStatus == "OK" else {
            throw AppError.streamUnavailable(payload.reason ?? "Ce morceau ne peut pas être lu.")
        }
        guard let url = payload.bestAudioURL else {
            throw AppError.streamUnavailable("Aucun flux audio compatible n’a été trouvé.")
        }
        return url
    }

    func getRelatedTracks(videoId: String) async throws -> [Track] {
        let radioPlaylistId = "RDAMVM\(videoId)"
        if let radioValue = try? await innerTubeClient.next(videoId: videoId, playlistId: radioPlaylistId) {
            let radioTracks = mapper.mapNextTracks(from: radioValue)
                .filter(\.musicGlassIsPlayableRecommendation)
                .filter { $0.videoId != videoId }
                .uniquedBy(\.id)
            if radioTracks.count >= 6 {
                return Array(radioTracks.prefix(30))
            }
        }

        let nextValue = try await innerTubeClient.next(videoId: videoId)
        return mapper.mapNextTracks(from: nextValue)
            .filter(\.musicGlassIsPlayableRecommendation)
            .filter { $0.videoId != videoId }
            .uniquedBy(\.id)
            .prefix(30)
            .map { $0 }
    }

    func getLyrics(videoId: String, metadata: Track) async throws -> Lyrics? {
        try await lyricsService.lyrics(for: metadata)
    }

    func getSuggestions(query: String) async throws -> [String] {
        let value = try await innerTubeClient.searchSuggestions(query: query)
        return mapper.mapSuggestions(from: value)
    }

    func getLikedSongs() async throws -> [Track] {
        let value = try await innerTubeClient.likedSongs()
        debugDumpJSON(value, filename: "liked_songs")
        let result = mapper.mapLikedSongs(from: value)
        AppLogger.youtube.notice("mapLikedSongs: found \(result.count) tracks")
        return result
    }

    func getUserPlaylists() async throws -> [Playlist] {
        let value = try await innerTubeClient.userPlaylists()
        debugDumpJSON(value, filename: "user_playlists")
        let result = mapper.mapUserPlaylists(from: value)
        AppLogger.youtube.notice("mapUserPlaylists: found \(result.count) playlists")
        return result
    }

    func getYTHistory() async throws -> [Track] {
        let value = try await innerTubeClient.ytHistory()
        debugDumpJSON(value, filename: "yt_history")
        let result = mapper.mapYTHistory(from: value)
        AppLogger.youtube.notice("mapYTHistory: found \(result.count) tracks")
        return result
    }

    func setLike(videoId: String, liked: Bool) async throws {
        try await innerTubeClient.setLike(videoId: videoId, liked: liked)
    }

    private func debugDumpJSON(_ value: JSONValue, filename: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("\(filename)_debug.json")
        try? data.write(to: url)
        AppLogger.youtube.notice("Dumped \(filename) JSON (\(data.count) bytes) to \(url.path, privacy: .public)")
    }

    private func applyLocalFilter(_ result: SearchResult, filter: SearchFilter?) -> SearchResult {
        guard let filter, filter != .all else { return result }
        switch filter {
        case .all:
            return result
        case .songs:
            return SearchResult(tracks: result.tracks, albums: [], artists: [], playlists: [], videos: [])
        case .albums:
            return SearchResult(tracks: [], albums: result.albums, artists: [], playlists: [], videos: [])
        case .artists:
            return SearchResult(tracks: [], albums: [], artists: result.artists, playlists: [], videos: [])
        case .playlists, .featuredPlaylists, .communityPlaylists:
            return SearchResult(tracks: [], albums: [], artists: [], playlists: result.playlists, videos: [])
        case .videos:
            return SearchResult(tracks: [], albums: [], artists: [], playlists: [], videos: result.videos)
        }
    }

    private func sanitize(_ result: SearchResult) -> SearchResult {
        SearchResult(
            tracks: result.tracks.filter(\.musicGlassIsLikelyMusicTrack),
            albums: result.albums.filter(\.musicGlassIsLikelyMusicAlbum),
            artists: result.artists,
            playlists: result.playlists.filter(\.musicGlassIsLikelyMusicPlaylist),
            videos: result.videos.filter(\.musicGlassIsLikelyMusicTrack)
        )
    }

    private func artworkEnrichedTracks(
        _ tracks: [Track],
        fallbackAlbum: Album? = nil,
        limit: Int = 80
    ) async -> [Track] {
        guard !tracks.isEmpty else { return tracks }

        var result = tracks
        let cappedCount = min(limit, tracks.count)
        let parallelism = min(6, cappedCount)

        await withTaskGroup(of: (Int, Track).self) { group in
            var nextIndex = 0

            while nextIndex < parallelism {
                let index = nextIndex
                let track = tracks[index]
                group.addTask {
                    (index, await artworkEnrichedTrack(track, fallbackAlbum: fallbackAlbum))
                }
                nextIndex += 1
            }

            while let (index, enrichedTrack) = await group.next() {
                result[index] = enrichedTrack

                if nextIndex < cappedCount {
                    let index = nextIndex
                    let track = tracks[index]
                    group.addTask {
                        (index, await artworkEnrichedTrack(track, fallbackAlbum: fallbackAlbum))
                    }
                    nextIndex += 1
                }
            }
        }

        return result
    }

    private func artworkEnrichedTrack(_ track: Track, fallbackAlbum: Album?) async -> Track {
        var enriched = track
        if enriched.album == nil, let fallbackAlbum {
            enriched.album = fallbackAlbum
        }

        let cacheKey = track.musicGlassArtworkCacheKey
        if let cached = await Self.artworkCache.track(for: cacheKey) {
            return enriched.mergingArtwork(from: cached, fallbackAlbum: fallbackAlbum)
        }

        guard let match = await bestArtworkMatch(for: track), !match.thumbnails.isEmpty else {
            return enriched
        }

        await Self.artworkCache.store(match, for: cacheKey)
        return enriched.mergingArtwork(from: match, fallbackAlbum: fallbackAlbum)
    }

    private func bestArtworkMatch(for track: Track) async -> Track? {
        let artist = track.artistLine
        let query = [track.title, artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty,
              let result = try? await search(query: query, filter: .songs)
        else { return nil }

        let candidates = (result.tracks + result.videos)
            .filter { !$0.thumbnails.isEmpty }

        return candidates.first { $0.musicGlassArtworkIsStrongMatch(for: track) }
            ?? candidates.first { $0.musicGlassArtworkSharesArtist(with: track) }
            ?? candidates.first { $0.title.musicGlassTitleStem == track.title.musicGlassTitleStem }
    }
}

private extension Track {
    var musicGlassIsLikelyMusicTrack: Bool {
        let folded = ([title, artistLine, album?.title ?? ""]).joined(separator: " ").musicGlassFolded
        guard !folded.hasMusicGlassBlockedMusicSignal else { return false }
        if let duration {
            guard duration >= 25, duration <= 12 * 60 else { return false }
        } else if artistLine.musicGlassFolded.isEmpty || folded.hasMusicGlassAmbiguousLongFormSignal {
            return false
        }
        return true
    }

    var musicGlassIsPlayableRecommendation: Bool {
        musicGlassIsLikelyMusicTrack && !artistLine.musicGlassFolded.isEmpty
    }

    func musicGlassArtworkIsStrongMatch(for original: Track) -> Bool {
        title.musicGlassTitleStem == original.title.musicGlassTitleStem &&
            musicGlassArtworkSharesArtist(with: original)
    }

    func musicGlassArtworkSharesArtist(with original: Track) -> Bool {
        let lhs = artistLine.musicGlassArtistTokens
        let rhs = original.artistLine.musicGlassArtistTokens
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return !Set(lhs).isDisjoint(with: Set(rhs))
    }

    var musicGlassArtworkCacheKey: String {
        "\(title.musicGlassTitleStem)|\(artistLine.musicGlassArtistTokens.joined(separator: ","))"
    }

    func mergingArtwork(from match: Track, fallbackAlbum: Album?) -> Track {
        var merged = self
        if merged.album == nil, let fallbackAlbum {
            merged.album = fallbackAlbum
        }
        if !match.thumbnails.isEmpty {
            merged.thumbnails = match.thumbnails
        }
        if merged.artists.isEmpty, !match.artists.isEmpty {
            merged.artists = match.artists
        }
        if merged.album == nil {
            merged.album = match.album ?? fallbackAlbum
        } else if var album = merged.album, album.thumbnails.isEmpty {
            album.thumbnails = match.album?.thumbnails ?? match.thumbnails
            merged.album = album
        }
        return merged
    }
}

private actor ArtworkEnrichmentCache {
    private var tracksByKey: [String: Track] = [:]

    func track(for key: String) -> Track? {
        tracksByKey[key]
    }

    func store(_ track: Track, for key: String) {
        tracksByKey[key] = track
    }
}

private extension String {
    var musicGlassPlainPlaylistId: String? {
        let raw = hasPrefix("VL") ? String(dropFirst(2)) : self
        guard raw == "LM" || raw.hasPrefix("PL") || raw.hasPrefix("OLAK5uy_") || raw.hasPrefix("RD") else {
            return nil
        }
        return raw
    }
}

private extension Album {
    var musicGlassIsLikelyMusicAlbum: Bool {
        let folded = ([title, artistLine]).joined(separator: " ").musicGlassFolded
        return !folded.hasMusicGlassBlockedMusicSignal && !folded.hasMusicGlassAmbiguousLongFormSignal
    }
}

private extension Playlist {
    var musicGlassIsLikelyMusicPlaylist: Bool {
        let folded = ([title, author ?? "", description ?? ""]).joined(separator: " ").musicGlassFolded
        return !folded.hasMusicGlassBlockedMusicSignal && !folded.hasMusicGlassPlaylistBlockedSignal
    }
}

private extension String {
    var musicGlassFolded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var musicGlassTitleStem: String {
        var text = musicGlassFolded
        for pair in [("(", ")"), ("[", "]"), ("{", "}")] {
            while let start = text.range(of: pair.0),
                  let end = text.range(of: pair.1, range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        let separators = CharacterSet.alphanumerics.inverted
        return text
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var musicGlassArtistTokens: [String] {
        musicGlassFolded
            .replacingOccurrences(of: "&", with: ",")
            .replacingOccurrences(of: " feat. ", with: ",")
            .replacingOccurrences(of: " ft. ", with: ",")
            .replacingOccurrences(of: " avec ", with: ",")
            .components(separatedBy: CharacterSet(charactersIn: ",/;|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "various artists" && $0 != "unknown artist" }
    }

    var hasMusicGlassBlockedMusicSignal: Bool {
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

    var hasMusicGlassAmbiguousLongFormSignal: Bool {
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

    var hasMusicGlassPlaylistBlockedSignal: Bool {
        contains("1 hour") ||
            contains("2 hour") ||
            contains("3 hour") ||
            contains("1h") ||
            contains("2h") ||
            contains("3h") ||
            contains("heure") ||
            contains("mix 202") ||
            contains("video mix") ||
            contains("clips") ||
            contains("clip officiel") ||
            contains("karaoke") ||
            contains("live stream")
    }
}
