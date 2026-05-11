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
        if filter == nil || filter == .all {
            async let allTask = searchWithFallback(query: query, filter: nil)
            async let artistsTask = searchWithFallback(query: query, filter: .artists)
            async let songsTask = searchWithFallback(query: "\(query) meilleurs titres", filter: .songs)
            async let albumsTask = searchWithFallback(query: "\(query) albums", filter: .albums)
            
            let all = await allTask
            let artistsSearch = await artistsTask
            let songsSearch = await songsTask
            let albumsSearch = await albumsTask
            
            var allArtists = (artistsSearch.artists + all.artists).uniquedBy(\.id)
            allArtists.sort { a1, a2 in
                if a1.name.caseInsensitiveCompare(query) == .orderedSame && a2.name.caseInsensitiveCompare(query) != .orderedSame { return true }
                return false
            }
            
            let allSongs = (songsSearch.tracks + all.tracks).uniquedBy(\.id)
            let allAlbums = (albumsSearch.albums + all.albums).uniquedBy(\.id)
            
            let merged = SearchResult(
                tracks: Array(allSongs.prefix(20)),
                albums: Array(allAlbums.prefix(14)),
                artists: Array(allArtists.prefix(6)),
                playlists: Array(all.playlists.prefix(12)),
                videos: all.videos
            )
            return applyLocalFilter(sanitize(merged), filter: filter)
        } else {
            let value = try await innerTubeClient.search(query: query, filter: filter)
            let result = mapper.mapSearchResult(from: value)
            guard !result.isEmpty else {
                return .empty
            }
            return applyLocalFilter(sanitize(result), filter: filter)
        }
    }

    private func searchWithFallback(query: String, filter: SearchFilter?) async -> SearchResult {
        do {
            let value = try await innerTubeClient.search(query: query, filter: filter)
            return mapper.mapSearchResult(from: value)
        } catch {
            return .empty
        }
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
        let candidates = [browseId, browseId.hasPrefix("VL") ? browseId : "VL\(browseId)"].uniqued()

        for candidate in candidates {
            if let value = try? await innerTubeClient.browse(browseId: candidate, useAuth: false) {
                let playlist = mapper.mapPlaylist(from: value, browseId: candidate)
                if !playlist.tracks.isEmpty { return await enrichWithQueue(playlist, candidate) }
            }
            if let value = try? await innerTubeClient.browse(browseId: candidate, useAuth: true) {
                let playlist = mapper.mapPlaylist(from: value, browseId: candidate)
                if !playlist.tracks.isEmpty { return await enrichWithQueue(playlist, candidate) }
            }
        }

        let fallbackValue = try await innerTubeClient.browse(browseId: browseId, useAuth: true)
        let fallbackPlaylist = mapper.mapPlaylist(from: fallbackValue, browseId: browseId)
        return await enrichWithQueue(fallbackPlaylist, browseId)
    }

    private func enrichWithQueue(_ playlist: Playlist, _ browseId: String) async -> Playlist {
        var enriched = playlist
        if enriched.tracks.isEmpty, let playlistId = browseId.musicGlassPlainPlaylistId,
           let queueValue = try? await innerTubeClient.playlistQueue(playlistId: playlistId) {
            var seenTrackIds = Set<String>()
            let tracks = mapper.mapNextTracks(from: queueValue)
                .filter(\.musicGlassIsLikelyMusicTrack)
                .filter { track in
                    guard !seenTrackIds.contains(track.id) else { return false }
                    seenTrackIds.insert(track.id)
                    return true
                }
            if !tracks.isEmpty {
                enriched.tracks = tracks
                enriched.trackCount = tracks.count
            }
        }
        enriched.trackCount = enriched.tracks.count
        return enriched
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

enum MusicAIIntentType: String, Codable {
    case playTrack, playPopularTrack, playLatestTrack
    case playAlbum, playLatestAlbum, playPopularAlbum
    case openAlbum, openArtist, openPlaylist, listAlbums, listTracks
    case playArtistMix, playPlaylist, playLikedSongs
    case playHistory, playMood, playGenre, playDecade, playSimilarTo
    case playNewReleases, playRecommended
    case searchAndShow
    case chatResponse, unknown
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = MusicAIIntentType(rawValue: rawValue) ?? .unknown
    }
}

struct MusicAIIntent: Codable, Hashable {
    let type: MusicAIIntentType
    let artistName: String?
    let trackTitle: String?
    let albumTitle: String?
    let playlistName: String?
    let mood: String?
    let genre: String?
    let decade: String?
    let similarToTrack: String?
    let similarToArtist: String?
    let language: String?
    let confidence: Double
    let shouldOpenFullPlayer: Bool
    let requiresUserChoice: Bool
    let clarificationQuestion: String?
    let chatResponseText: String?
}

enum DeepSeekError: Error, LocalizedError {
    case invalidURL, noResponse, decodeError, apiError(String), invalidKey
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL DeepSeek invalide."
        case .noResponse: return "Aucune réponse de DeepSeek."
        case .decodeError: return "Je n'ai pas pu comprendre la réponse de l'IA. Réessayez ou reformulez."
        case .apiError(let msg): return "Erreur API DeepSeek : \(msg)"
        case .invalidKey: return "Clé API DeepSeek non configurée."
        }
    }
}

@MainActor
final class DeepSeekMusicIntentService {
    private let apiKey = "sk-d7fa95872d1e4f3187f661e9459ac139"
    private let endpoint = "https://api.deepseek.com/chat/completions"
    
    func parseIntent(from text: String) async throws -> MusicAIIntent {
        guard !apiKey.isEmpty && !apiKey.contains("PLACEHOLDER") else { throw DeepSeekError.invalidKey }
        guard let url = URL(string: endpoint) else { throw DeepSeekError.invalidURL }
        
        let systemPrompt = """
        Tu es un assistant musical intelligent pour MusicGlass. Réponds UNIQUEMENT avec un objet JSON valide. Aucun texte avant ou après. Aucun bloc ```json.

        TON RÔLE : Comprendre ce que l'utilisateur veut faire avec sa musique.

        === LECTURE DIRECTE (lance la musique) ===
        - playTrack : "joue [titre] de [artiste]", "lance [titre]"
        - playPopularTrack : "joue le plus populaire de [artiste]", "le hit de [artiste]"
        - playLatestTrack : "joue le nouveau single de [artiste]"
        - playAlbum : "joue l'album [album] de [artiste]", "lance [album]"
        - playLatestAlbum : "joue le dernier album de [artiste]"
        - playArtistMix : "joue [artiste]", "mix de [artiste]", "je veux écouter [artiste]"
        - playPlaylist : "joue la playlist [nom]", "lance la playlist [nom]"
        - playLikedSongs : "joue mes favoris", "mes likes", "joue mes titres likés"
        - playHistory : "joue mon historique", "rejoue ce que j'ai écouté"
        - playMood : "musique relaxante", "joue du jazz calme", "musique pour dormir" -> utilise mood
        - playGenre : "joue du rock", "je veux du rap français", "musique électronique" -> utilise genre
        - playDecade : "joue des hits des années 80", "musique années 90" -> utilise decade
        - playSimilarTo : "joue des morceaux comme [titre]", "quelque chose comme [artiste]" -> utilise similarToTrack/similarToArtist
        - playNewReleases : "nouveautés", "dernières sorties", "nouveaux albums"
        - playRecommended : "recommande moi", "suggestions", "que me conseilles-tu"

        === NAVIGATION (ouvre une page) ===
        - openArtist : "ouvre la page de [artiste]", "montre [artiste]", "va sur [artiste]"
        - openAlbum : "ouvre l'album [album]", "montre l'album [album]"
        - openPlaylist : "ouvre la playlist [nom]", "montre la playlist [nom]"
        - listAlbums : "montre les albums de [artiste]", "discographie de [artiste]"

        === RECHERCHE ===
        - searchAndShow : "recherche [terme]", "cherche [terme]", "trouve [terme]"

        === CONVERSATION ===
        - chatResponse : questions non musicales, salutations, "merci", "comment ça va" -> utilise chatResponseText

        CHAMPS JSON : type, artistName, trackTitle, albumTitle, playlistName, mood, genre, decade, similarToTrack, similarToArtist, language, confidence (0.0-1.0), shouldOpenFullPlayer, requiresUserChoice, clarificationQuestion, chatResponseText.
        """
        
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.1
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw DeepSeekError.noResponse }
        
        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Erreur \(httpResponse.statusCode)"
            throw DeepSeekError.apiError(errorMsg)
        }
        
        struct DSResp: Codable { struct Choice: Codable { struct Msg: Codable { let content: String }; let message: Msg }; let choices: [Choice] }
        let dsResp = try JSONDecoder().decode(DSResp.self, from: data)
        guard let rawContent = dsResp.choices.first?.message.content else { throw DeepSeekError.decodeError }
        
        let cleanedContent = extractJSON(from: rawContent)
        guard let jsonData = cleanedContent.data(using: .utf8) else { throw DeepSeekError.decodeError }
        
        do {
            let intent = try JSONDecoder().decode(MusicAIIntent.self, from: jsonData)
            print("🎙️ [DeepSeek] Intent: \(intent.type) | Action: \(intent.requiresUserChoice ? "List" : "Direct")")
            return intent
        } catch {
            print("🎙️ [DeepSeek] JSON Decode Error: \(error)")
            throw DeepSeekError.decodeError
        }
    }
    
    private func extractJSON(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}"),
           start <= end {
            return String(cleaned[start...end])
        }
        return cleaned
    }
}

enum MusicAIResolution {
    case playableTrack(Track, [Track])
    case playableAlbum(Album, [Track])
    case playablePlaylist(Playlist, [Track])
    case playableRadio(Track)
    case albumList([Album])
    case openSearch(String)
    case navigateToArtist(browseId: String, name: String)
    case navigateToAlbum(browseId: String, title: String)
    case navigateToPlaylist(browseId: String, title: String)
    case searchResults(query: String)
    case chatResponse(String)
    case needsClarification(String)
    case failure(String)
}

@MainActor
final class MusicAIResolver {
    private let client: YouTubeMusicClientProtocol
    init(client: YouTubeMusicClientProtocol) { self.client = client }
    
    func resolve(intent: MusicAIIntent) async throws -> MusicAIResolution {
        guard intent.confidence >= 0.5 else { return .needsClarification(intent.clarificationQuestion ?? "Précisez votre demande.") }
        
        switch intent.type {
        case .playTrack: return try await resolveTrack(intent)
        case .playPopularTrack: return try await resolvePopularTrack(intent)
        case .playLatestTrack: return try await resolveLatestTrack(intent)
        case .playAlbum: return try await resolveAlbum(intent)
        case .playLatestAlbum: return try await resolveLatestAlbum(intent)
        case .openAlbum: return try await resolveOpenAlbum(intent)
        case .openArtist: return try await resolveOpenArtist(intent)
        case .openPlaylist: return try await resolveOpenPlaylist(intent)
        case .listAlbums: return try await resolveListAlbums(intent)
        case .playPlaylist: return try await resolvePlaylist(intent)
        case .playLikedSongs: return try await resolveLikedSongs()
        case .playArtistMix: return try await resolveArtistMix(intent)
        case .playHistory: return try await resolveHistory(intent)
        case .playMood: return try await resolveMood(intent)
        case .playGenre: return try await resolveGenre(intent)
        case .playDecade: return try await resolveDecade(intent)
        case .playSimilarTo: return try await resolveSimilarTo(intent)
        case .playNewReleases: return try await resolveNewReleases()
        case .playRecommended: return try await resolveRecommended()
        case .searchAndShow: return .searchResults(query: [intent.artistName, intent.trackTitle, intent.albumTitle].compactMap{$0}.joined(separator: " "))
        case .chatResponse: return .chatResponse(intent.chatResponseText ?? "Je suis votre assistant musical. Que voulez-vous écouter ?")
        default: return .openSearch(String([intent.artistName, intent.trackTitle].compactMap{$0}.joined(separator: " ")))
        }
    }
    
    private func resolveTrack(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let q = [intent.trackTitle, intent.artistName].compactMap{$0}.joined(separator: " ")
        let res = try await client.search(query: q, filter: .songs)
        return res.tracks.isEmpty ? .failure("Titre non trouvé") : .playableTrack(res.tracks[0], res.tracks)
    }
    
    private func resolvePopularTrack(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let q = "\(intent.artistName ?? "") meilleurs titres"
        let res = try await client.search(query: q, filter: .songs)
        return res.tracks.isEmpty ? .failure("Titres populaires non trouvés") : .playableTrack(res.tracks[0], Array(res.tracks.prefix(10)))
    }
    
    private func resolveLatestTrack(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let q = "\(intent.artistName ?? "") nouveau single"
        let res = try await client.search(query: q, filter: .songs)
        return res.tracks.isEmpty ? .failure("Nouveau titre non trouvé") : .playableTrack(res.tracks[0], res.tracks)
    }
    
    private func resolveAlbum(_ intent: MusicAIIntent, openOnly: Bool = false) async throws -> MusicAIResolution {
        let q = [intent.albumTitle, intent.artistName].compactMap{$0}.joined(separator: " ")
        let res = try await client.search(query: q, filter: .albums)
        if let id = res.albums.first?.browseId {
            let alb = try await client.getAlbum(browseId: id)
            return .playableAlbum(alb, alb.tracks)
        }
        return .failure("Album non trouvé")
    }
    
    private func resolveLatestAlbum(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let res = try await client.search(query: intent.artistName ?? "", filter: .artists)
        if let artistId = res.artists.first?.browseId {
            let page = try await client.getArtist(browseId: artistId)
            let allAlbums = (page.albums + page.singles).filter { $0.browseId != nil }
            if let latest = allAlbums.first { 
                let alb = try await client.getAlbum(browseId: latest.browseId!)
                if !alb.tracks.isEmpty {
                    return .playableAlbum(alb, alb.tracks)
                }
            }
        }
        return .failure("Dernier album non trouvé ou vide")
    }
    
    private func resolveListAlbums(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let res = try await client.search(query: intent.artistName ?? "", filter: .artists)
        if let artistId = res.artists.first?.browseId {
            let page = try await client.getArtist(browseId: artistId)
            var seenIds = Set<String>()
            let allAlbums = (page.albums + page.singles)
                .filter { album in
                    guard let bid = album.browseId, !seenIds.contains(bid) else { return false }
                    seenIds.insert(bid)
                    return true
                }
            return allAlbums.isEmpty ? .failure("Aucun album trouvé") : .albumList(allAlbums)
        }
        return .failure("Artiste non trouvé")
    }
    
    private func resolvePlaylist(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let res = try await client.search(query: intent.playlistName ?? "", filter: .playlists)
        if let id = res.playlists.first?.browseId {
            let pl = try await client.getPlaylist(browseId: id)
            return .playablePlaylist(pl, pl.tracks)
        }
        return .failure("Playlist non trouvée")
    }
    
    private func resolveLikedSongs() async throws -> MusicAIResolution {
        let tracks = try await client.getLikedSongs()
        return tracks.isEmpty ? .failure("Favoris vides") : .playableTrack(tracks[0], tracks)
    }
    
    private func resolveArtistMix(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let res = try await client.search(query: intent.artistName ?? "", filter: .artists)
        if let id = res.artists.first?.browseId {
            let page = try await client.getArtist(browseId: id)
            if let first = page.topTracks.first { return .playableRadio(first) }
        }
        return .failure("Mix artiste impossible")
    }

    private func resolveHistory(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let tracks = try await client.getYTHistory()
        return tracks.isEmpty ? .failure("Historique vide") : .playableTrack(tracks[0], tracks)
    }

    private func resolveMood(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let q = intent.mood ?? "musique"
        let res = try await client.search(query: q, filter: .songs)
        return res.tracks.isEmpty ? .failure("Aucun résultat pour cette humeur") : .playableTrack(res.tracks[0], res.tracks)
    }

    private func resolveGenre(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let q = intent.genre ?? intent.mood ?? "musique"
        let res = try await client.search(query: q, filter: .songs)
        return res.tracks.isEmpty ? .failure("Aucun résultat pour ce genre") : .playableTrack(res.tracks[0], res.tracks)
    }

    private func resolveDecade(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let q = "hits \(intent.decade ?? "")"
        let res = try await client.search(query: q, filter: .songs)
        return res.tracks.isEmpty ? .failure("Aucun résultat pour cette décennie") : .playableTrack(res.tracks[0], res.tracks)
    }

    private func resolveSimilarTo(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let q = intent.similarToTrack ?? intent.similarToArtist ?? intent.trackTitle ?? ""
        let res = try await client.search(query: q, filter: .songs)
        let tracks = Array(res.tracks.dropFirst().prefix(20))
        return res.tracks.isEmpty ? .failure("Aucune recommandation similaire") : .playableTrack(res.tracks[0], tracks)
    }

    private func resolveNewReleases() async throws -> MusicAIResolution {
        let feed = try await client.getHome()
        var allTracks: [Track] = []
        for section in feed.sections {
            for item in section.items {
                if case .track(let t) = item { allTracks.append(t) }
            }
        }
        return allTracks.isEmpty ? .failure("Aucune nouveauté disponible") : .playableTrack(allTracks[0], Array(allTracks.prefix(30)))
    }

    private func resolveRecommended() async throws -> MusicAIResolution {
        let feed = try await client.getHome()
        var allTracks: [Track] = []
        for section in feed.sections {
            for item in section.items {
                if case .track(let t) = item { allTracks.append(t) }
            }
        }
        return allTracks.isEmpty ? .failure("Aucune recommandation disponible") : .playableTrack(allTracks[0], Array(allTracks.shuffled().prefix(20)))
    }

    private func resolveOpenArtist(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let q = intent.artistName ?? ""
        let res = try await client.search(query: q, filter: .artists)
        if let artist = res.artists.first, let browseId = artist.browseId {
            return .navigateToArtist(browseId: browseId, name: artist.name)
        }
        return .failure("Artiste non trouvé")
    }

    private func resolveOpenAlbum(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let q = [intent.albumTitle, intent.artistName].compactMap{$0}.joined(separator: " ")
        let res = try await client.search(query: q, filter: .albums)
        if let album = res.albums.first, let browseId = album.browseId {
            return .navigateToAlbum(browseId: browseId, title: album.title)
        }
        return .failure("Album non trouvé")
    }

    private func resolveOpenPlaylist(_ intent: MusicAIIntent) async throws -> MusicAIResolution {
        let q = intent.playlistName ?? ""
        let res = try await client.search(query: q, filter: .playlists)
        if let playlist = res.playlists.first, let browseId = playlist.browseId {
            return .navigateToPlaylist(browseId: browseId, title: playlist.title)
        }
        return .failure("Playlist non trouvée")
    }
}
