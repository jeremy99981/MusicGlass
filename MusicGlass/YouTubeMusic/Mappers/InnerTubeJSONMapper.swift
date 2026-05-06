import Foundation

struct InnerTubeJSONMapper: Sendable {
    func mapSearchResult(from value: JSONValue) -> SearchResult {
        var tracks: [Track] = []
        var videos: [Track] = []
        var albums: [Album] = []
        var artists: [Artist] = []
        var playlists: [Playlist] = []

        for renderer in value.collectObjects(named: "musicResponsiveListItemRenderer") {
            switch mapResponsiveRenderer(renderer) {
            case .track(let track):
                if isLikelyMusicVideo(renderer) {
                    videos.append(track)
                } else {
                    tracks.append(track)
                }
            case .album(let album):
                albums.append(album)
            case .artist(let artist):
                artists.append(artist)
            case .playlist(let playlist):
                playlists.append(playlist)
            case .none:
                break
            }
        }

        for renderer in value.collectObjects(named: "musicTwoRowItemRenderer") {
            switch mapTwoRowRenderer(renderer) {
            case .track(let track):
                videos.append(track)
            case .album(let album):
                albums.append(album)
            case .artist(let artist):
                artists.append(artist)
            case .playlist(let playlist):
                playlists.append(playlist)
            case .none:
                break
            }
        }

        return SearchResult(
            tracks: tracks.uniquedBy(\.id),
            albums: albums.uniquedBy(\.id),
            artists: artists.uniquedBy(\.id),
            playlists: playlists.uniquedBy(\.id),
            videos: videos.uniquedBy(\.id)
        )
    }

    func mapHomeFeed(from value: JSONValue) -> HomeFeed {
        var sections = value.collectObjects(named: "musicCarouselShelfRenderer").compactMap { carousel -> HomeSection? in
            let title = text(from: carousel.value(at: ["header", "musicCarouselShelfBasicHeaderRenderer", "title"]))
                ?? text(from: carousel.value(at: ["header", "musicImmersiveCarouselShelfBasicHeaderRenderer", "title"]))
                ?? "For You"
            let items = homeItems(from: carousel["contents"]?.array ?? [])
            guard !items.isEmpty else { return nil }
            return HomeSection(id: stableId("home-\(title)"), title: title, items: items.uniquedBy(\.id))
        }

        let shelfSections = value.collectObjects(named: "musicShelfRenderer").compactMap { shelf -> HomeSection? in
            let title = text(from: shelf["title"]) ?? "Suggestions"
            let items = homeItems(from: shelf["contents"]?.array ?? [])
            guard !items.isEmpty else { return nil }
            return HomeSection(id: stableId("home-shelf-\(title)"), title: title, items: items.uniquedBy(\.id))
        }
        sections.append(contentsOf: shelfSections)

        let gridItems = value.collectObjects(named: "gridRenderer")
            .flatMap { grid in homeItems(from: grid["items"]?.array ?? grid["contents"]?.array ?? []) }
            .uniquedBy(\.id)
        if !gridItems.isEmpty {
            sections.append(HomeSection(id: "home-grid-recommendations", title: "Recommandations", items: gridItems))
        }
        return HomeFeed(sections: sections.uniquedBy(\.id))
    }

    func mapAlbum(from value: JSONValue, browseId: String) -> Album {
        let title = headerTitle(from: value) ?? "Album"
        let thumbnails = headerThumbnails(from: value)
        let parsedTracks = value.collectObjects(named: "musicResponsiveListItemRenderer")
            .compactMap { renderer -> Track? in
                guard case .track(let track)? = mapResponsiveRenderer(renderer) else { return nil }
                return track
            }
            .uniquedBy(\.id)
        let titleKey = stableId(title)
        let trackArtists = parsedTracks
            .flatMap(\.artists)
            .filter { !$0.name.musicGlassIsGenericMusicRoleLabel && stableId($0.name) != titleKey }
            .uniquedBy(\.id)
        let headerArtists = headerArtists(from: value, title: title)
        let inferredArtists = dominantAlbumArtists(from: parsedTracks, albumTitle: title)
        let artists = headerArtists
            .ifEmpty(inferredArtists)
            .ifEmpty(trackArtists)
        let albumContext = Album(
            id: browseId,
            browseId: browseId,
            title: title,
            artists: artists,
            year: firstYear(in: value),
            thumbnails: thumbnails
        )
        let tracks = parsedTracks.map { track -> Track in
            var track = track
            // Force album context when missing or incomplete so row artwork stays consistent
            // with the opened album cover.
            if track.album == nil || (track.album?.thumbnails.isEmpty ?? true) {
                track.album = albumContext
            }
            if !thumbnails.isEmpty {
                track.thumbnails = thumbnails
            }
            if !artists.isEmpty {
                track.artists = artists
            }
            return track
        }
        return Album(
            id: browseId,
            browseId: browseId,
            title: title,
            artists: artists,
            year: firstYear(in: value),
            thumbnails: thumbnails,
            tracks: tracks
        )
    }

    func mapArtistPage(from value: JSONValue, browseId: String) -> ArtistPage {
        let name = headerTitle(from: value) ?? "Artist"
        let artist = Artist(id: browseId, browseId: browseId, name: name, thumbnails: headerThumbnails(from: value))
        let result = mapSearchResult(from: value)
        return ArtistPage(
            artist: artist,
            topTracks: result.tracks,
            albums: result.albums,
            singles: [],
        )
    }

    func mapPlaylist(from value: JSONValue, browseId: String) -> Playlist {
        let title = headerTitle(from: value) ?? "Playlist"
        let musicTracks = value.collectObjects(named: "musicResponsiveListItemRenderer")
            .compactMap { renderer -> Track? in
                guard case .track(let track)? = mapResponsiveRenderer(renderer) else { return nil }
                return track
            }
        let youtubePlaylistTracks = value.collectObjects(named: "playlistVideoRenderer")
            .compactMap(mapPlainVideoRenderer)
        let youtubeVideoTracks = musicTracks.isEmpty ? value.collectObjects(named: "videoRenderer")
            .compactMap(mapPlainVideoRenderer) : []
        let tracks = (musicTracks + youtubePlaylistTracks + youtubeVideoTracks)
            .uniquedBy(\.id)
        let description = value.collectObjects(named: "description").compactMap { text(from: $0) }.first
        return Playlist(
            id: browseId.removePrefix("VL"),
            browseId: browseId,
            title: title,
            author: firstByline(in: value),
            description: description,
            thumbnails: headerThumbnails(from: value),
            tracks: tracks,
            trackCount: tracks.count
        )
    }

    func mapPlayerPayload(from value: JSONValue, videoId: String) -> PlayerPayload {
        let status = value.string(at: ["playabilityStatus", "status"]) ?? "UNKNOWN"
        let reason = value.string(at: ["playabilityStatus", "reason"])
        let videoDetails = value["videoDetails"]
        let title = videoDetails?.string(at: ["title"]) ?? "Titre inconnu"
        let author = videoDetails?.string(at: ["author"])
        let lengthSeconds = videoDetails?.string(at: ["lengthSeconds"]).flatMap(TimeInterval.init)
        let thumbnails = thumbnails(from: videoDetails?.value(at: ["thumbnail", "thumbnails"]))
        let formats = (value.value(at: ["streamingData", "adaptiveFormats"])?.array ?? [])
            .compactMap(mapPlayerFormat)

        return PlayerPayload(
            videoId: videoId,
            title: title,
            author: author,
            duration: lengthSeconds,
            thumbnails: thumbnails,
            formats: formats,
            playabilityStatus: status,
            reason: reason,
            hlsManifestURL: value.string(at: ["streamingData", "hlsManifestUrl"]).flatMap(URL.init(string:)),
            serverAbrStreamingURL: value.string(at: ["streamingData", "serverAbrStreamingUrl"]).flatMap(URL.init(string:))
        )
    }

    func mapNextTracks(from value: JSONValue) -> [Track] {
        value.collectObjects(named: "playlistPanelVideoRenderer")
            .compactMap(mapPlaylistPanelVideoRenderer)
            .uniquedBy(\.id)
    }

    func mapSuggestions(from value: JSONValue) -> [String] {
        value.collectObjects(named: "searchSuggestionRenderer")
            .compactMap { text(from: $0["suggestion"]) }
            .uniqued()
    }

    /// Map liked songs from FEmusic_liked_videos browse response
    func mapLikedSongs(from value: JSONValue) -> [Track] {
        value.collectObjects(named: "musicResponsiveListItemRenderer")
            .compactMap { renderer -> Track? in
                guard case .track(let track)? = mapResponsiveRenderer(renderer) else { return nil }
                return track
            }
            .uniquedBy(\.id)
    }

    /// Map user playlists from FEmusic_library_privately_owned_playlists browse response
    func mapUserPlaylists(from value: JSONValue) -> [Playlist] {
        var playlists: [Playlist] = []

        // Try musicTwoRowItemRenderer (grid layout)
        for renderer in value.collectObjects(named: "musicTwoRowItemRenderer") {
            if case .playlist(let playlist)? = mapTwoRowRenderer(renderer) {
                playlists.append(playlist)
            }
        }

        // Also try musicResponsiveListItemRenderer (list layout)
        if playlists.isEmpty {
            for renderer in value.collectObjects(named: "musicResponsiveListItemRenderer") {
                if case .playlist(let playlist)? = mapResponsiveRenderer(renderer) {
                    playlists.append(playlist)
                }
            }
        }

        return playlists
            .filter(\.musicGlassIsVisibleYouTubeMusicLibraryPlaylist)
            .uniquedBy(\.id)
    }

    /// Map YouTube Music history from FEmusic_history browse response
    func mapYTHistory(from value: JSONValue) -> [Track] {
        value.collectObjects(named: "musicResponsiveListItemRenderer")
            .compactMap { renderer -> Track? in
                guard case .track(let track)? = mapResponsiveRenderer(renderer) else { return nil }
                return track
            }
            .uniquedBy(\.id)
    }
}

private extension InnerTubeJSONMapper {
    enum MappedItem {
        case track(Track)
        case album(Album)
        case artist(Artist)
        case playlist(Playlist)

        var homeItem: HomeItem {
            switch self {
            case .track(let track): .track(track)
            case .album(let album): .album(album)
            case .artist(let artist): .artist(artist)
            case .playlist(let playlist): .playlist(playlist)
            }
        }
    }

    func homeItems(from contents: [JSONValue]) -> [HomeItem] {
        contents.compactMap { content -> HomeItem? in
            if let renderer = content["musicTwoRowItemRenderer"] {
                return mapTwoRowRenderer(renderer)?.homeItem
            }
            if let renderer = content["musicResponsiveListItemRenderer"] {
                return mapResponsiveRenderer(renderer)?.homeItem
            }
            if let renderer = content["musicMultiRowListItemRenderer"] {
                return mapResponsiveRenderer(renderer)?.homeItem
            }
            return nil
        }
    }

    func dominantAlbumArtists(from tracks: [Track], albumTitle: String) -> [Artist] {
        let albumKey = stableId(albumTitle)
        var counts: [String: Int] = [:]
        var artistsByKey: [String: Artist] = [:]

        for track in tracks {
            let trackArtists = track.artists
                .filter { !$0.name.musicGlassIsGenericMusicRoleLabel && stableId($0.name) != albumKey }
                .uniquedBy(\.id)
            for artist in trackArtists {
                let key = stableId(artist.name)
                guard !key.isEmpty else { continue }
                counts[key, default: 0] += 1
                artistsByKey[key] = artistsByKey[key] ?? artist
            }
        }

        guard let maxCount = counts.values.max(), maxCount >= 2 else { return [] }
        let minimumDominantCount = max(2, Int(ceil(Double(tracks.count) * 0.35)))
        guard maxCount >= minimumDominantCount else { return [] }

        return counts
            .filter { $0.value == maxCount }
            .compactMap { artistsByKey[$0.key] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func mapResponsiveRenderer(_ renderer: JSONValue) -> MappedItem? {
        let navigationPageType = renderer.value(at: ["navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType"])?.string
        let navigationBrowseId = renderer.value(at: ["navigationEndpoint", "browseEndpoint", "browseId"])?.string
        let directVideoId = renderer.value(at: ["playlistItemData", "videoId"])?.string
            ?? renderer.value(at: ["navigationEndpoint", "watchEndpoint", "videoId"])?.string

        let fallbackPageType = directVideoId == nil ? renderer.collectStrings(named: "pageType").first : nil
        let fallbackBrowseId = directVideoId == nil ? renderer.collectStrings(named: "browseId").first : nil
        let pageType = navigationPageType ?? fallbackPageType
        let browseId = navigationBrowseId ?? fallbackBrowseId

        let title = text(from: renderer.value(at: ["flexColumns", "0", "musicResponsiveListItemFlexColumnRenderer", "text"]))
            ?? text(from: renderer.value(at: ["flexColumns"])?.firstFlexColumnText)
            ?? text(from: renderer.value(at: ["title"]))
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title = cleanTitle, !title.isEmpty else { return nil }

        let baseThumbnails = thumbnails(from: renderer.value(at: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
            + thumbnails(from: renderer.value(at: ["thumbnail", "thumbnails"]))
        let secondaryText = text(from: renderer.value(at: ["flexColumns", "1", "musicResponsiveListItemFlexColumnRenderer", "text"]))
            ?? text(from: renderer["subtitle"])
            ?? text(from: renderer["longBylineText"])
            ?? text(from: renderer["shortBylineText"])
            ?? ""
        let fixedText = text(from: renderer.value(at: ["fixedColumns", "0", "musicResponsiveListItemFixedColumnRenderer", "text"])) ?? ""
        let secondaryRuns = splitRuns(
            renderer.value(at: ["flexColumns", "1", "musicResponsiveListItemFlexColumnRenderer", "text", "runs"])?.array
                ?? renderer.value(at: ["subtitle", "runs"])?.array
                ?? renderer.value(at: ["longBylineText", "runs"])?.array
                ?? renderer.value(at: ["shortBylineText", "runs"])?.array
                ?? []
        )
        let fixedRuns = splitRuns(
            renderer.value(at: ["fixedColumns", "0", "musicResponsiveListItemFixedColumnRenderer", "text", "runs"])?.array
                ?? []
        )
        let subtitle = secondaryText.isEmpty ? secondaryRuns.map(\.text).joined(separator: " ") : secondaryText
        let rendererKindText = ([title, subtitle, fixedText] + renderer.collectStrings(named: "pageType"))
            .joined(separator: " ")
            .musicGlassFolded
        if rendererKindText.hasMusicGlassBlockedPlayableSignal {
            return nil
        }

        if directVideoId == nil,
           pageType?.contains("ARTIST") == true || (subtitle.localizedCaseInsensitiveContains("artist") && browseId != nil) {
            return .artist(Artist(id: browseId ?? stableId(title), browseId: browseId, name: title, thumbnails: baseThumbnails))
        }

        if directVideoId == nil,
           pageType?.contains("ALBUM") == true || subtitle.localizedCaseInsensitiveContains("album") {
            let artists = artists(from: secondaryRuns, subtitle: subtitle)
            return .album(Album(
                id: browseId ?? stableId(title),
                browseId: browseId,
                title: title,
                artists: artists,
                year: secondaryRuns.compactMap { Int($0.text) }.first,
                thumbnails: baseThumbnails
            ))
        }

        if directVideoId == nil,
           pageType?.contains("PLAYLIST") == true || (browseId?.hasPrefix("VL") == true) || subtitle.localizedCaseInsensitiveContains("playlist") {
            return .playlist(Playlist(
                id: (browseId ?? stableId(title)).removePrefix("VL"),
                browseId: browseId,
                title: title,
                author: playlistAuthor(from: secondaryRuns, subtitle: subtitle),
                thumbnails: baseThumbnails,
                trackCount: trackCount(from: secondaryRuns, subtitle: subtitle)
            ))
        }

        guard let videoId = directVideoId
            ?? renderer.collectStrings(named: "videoId").first
        else {
            return nil
        }

        let thumbnails = (baseThumbnails + fallbackTrackThumbnails(videoId: videoId)).uniquedBy(\.url)
        let artists = artists(from: secondaryRuns, subtitle: subtitle)
        let album = album(from: secondaryRuns)
        let duration = (secondaryRuns + fixedRuns).reversed().compactMap { parseDuration($0.text) }.first
            ?? parseDuration(fixedText)
        return .track(Track(
            id: videoId,
            videoId: videoId,
            title: title,
            artists: artists,
            album: album,
            duration: duration,
            thumbnails: thumbnails,
            explicit: renderer.collectStrings(named: "iconType").contains("MUSIC_EXPLICIT_BADGE")
        ))
    }

    func mapTwoRowRenderer(_ renderer: JSONValue) -> MappedItem? {
        let title = text(from: renderer["title"]) ?? text(from: renderer.value(at: ["headline"]))
        guard let title, !title.isEmpty else { return nil }
        let navigationPageType = renderer.value(at: ["navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType"])?.string
        let navigationBrowseId = renderer.value(at: ["navigationEndpoint", "browseEndpoint", "browseId"])?.string
        let directVideoId = renderer.value(at: ["navigationEndpoint", "watchEndpoint", "videoId"])?.string
        let pageType = navigationPageType ?? (directVideoId == nil ? renderer.collectStrings(named: "pageType").first : nil)
        let browseId = navigationBrowseId ?? (directVideoId == nil ? renderer.collectStrings(named: "browseId").first : nil)
        let thumbnails = thumbnails(from: renderer.value(at: ["thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
            + thumbnails(from: renderer.value(at: ["thumbnail", "thumbnails"]))
        let subtitle = text(from: renderer["subtitle"])
            ?? text(from: renderer["longBylineText"])
            ?? text(from: renderer["shortBylineText"])
            ?? ""
        let rendererKindText = ([title, subtitle] + renderer.collectStrings(named: "pageType"))
            .joined(separator: " ")
            .musicGlassFolded
        if rendererKindText.hasMusicGlassBlockedPlayableSignal {
            return nil
        }

        if directVideoId == nil, pageType?.contains("ARTIST") == true {
            return .artist(Artist(id: browseId ?? stableId(title), browseId: browseId, name: title, thumbnails: thumbnails))
        }
        if directVideoId == nil, pageType?.contains("ALBUM") == true || subtitle.localizedCaseInsensitiveContains("album") {
            return .album(Album(id: browseId ?? stableId(title), browseId: browseId, title: title, thumbnails: thumbnails))
        }
        if directVideoId == nil, pageType?.contains("PLAYLIST") == true || browseId?.hasPrefix("VL") == true {
            let subtitleRuns = splitRuns(renderer.value(at: ["subtitle", "runs"])?.array ?? [])
            return .playlist(Playlist(
                id: (browseId ?? stableId(title)).removePrefix("VL"),
                browseId: browseId,
                title: title,
                author: playlistAuthor(from: subtitleRuns, subtitle: subtitle),
                thumbnails: thumbnails,
                trackCount: trackCount(from: subtitleRuns, subtitle: subtitle)
            ))
        }
        if let videoId = directVideoId ?? renderer.collectStrings(named: "videoId").first {
            return .track(Track(
                id: videoId,
                videoId: videoId,
                title: title,
                artists: subtitleArtists(from: subtitle),
                thumbnails: (thumbnails + fallbackTrackThumbnails(videoId: videoId)).uniquedBy(\.url)
            ))
        }
        return nil
    }

    func mapPlaylistPanelVideoRenderer(_ renderer: JSONValue) -> Track? {
        guard let videoId = renderer["videoId"]?.string,
              let title = text(from: renderer["title"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }

        let bylineRuns = splitRuns(
            renderer.value(at: ["longBylineText", "runs"])?.array
                ?? renderer.value(at: ["shortBylineText", "runs"])?.array
                ?? []
        )
        let subtitle = text(from: renderer["longBylineText"])
            ?? text(from: renderer["shortBylineText"])
            ?? ""
        let duration = text(from: renderer["lengthText"]).flatMap(parseDuration)
        let kindText = ([title, subtitle] + renderer.collectStrings(named: "pageType"))
            .joined(separator: " ")
            .musicGlassFolded
        if kindText.hasMusicGlassBlockedPlayableSignal {
            return nil
        }

        return Track(
            id: videoId,
            videoId: videoId,
            title: title,
            artists: artists(from: bylineRuns, subtitle: subtitle),
            album: album(from: bylineRuns),
            duration: duration,
            thumbnails: playlistItemThumbnails(from: renderer, videoId: videoId),
            explicit: renderer.collectStrings(named: "iconType").contains("MUSIC_EXPLICIT_BADGE")
        )
    }

    func mapPlainVideoRenderer(_ renderer: JSONValue) -> Track? {
        guard let videoId = renderer["videoId"]?.string,
              let title = text(from: renderer["title"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }

        let bylineRuns = splitRuns(
            renderer.value(at: ["longBylineText", "runs"])?.array
                ?? renderer.value(at: ["shortBylineText", "runs"])?.array
                ?? renderer.value(at: ["ownerText", "runs"])?.array
                ?? renderer.value(at: ["shortBylineText", "runs"])?.array
                ?? []
        )
        let subtitle = text(from: renderer["longBylineText"])
            ?? text(from: renderer["shortBylineText"])
            ?? text(from: renderer["ownerText"])
            ?? ""
        let duration = text(from: renderer["lengthText"]).flatMap(parseDuration)
            ?? text(from: renderer["lengthSeconds"]).flatMap(TimeInterval.init)
        let kindText = ([title, subtitle] + renderer.collectStrings(named: "pageType"))
            .joined(separator: " ")
            .musicGlassFolded
        if kindText.hasMusicGlassBlockedPlayableSignal {
            return nil
        }
        if let duration, duration < 25 || duration > 12 * 60 {
            return nil
        }

        return Track(
            id: videoId,
            videoId: videoId,
            title: title,
            artists: artists(from: bylineRuns, subtitle: subtitle),
            album: album(from: bylineRuns),
            duration: duration,
            thumbnails: playlistItemThumbnails(from: renderer, videoId: videoId),
            explicit: renderer.collectStrings(named: "iconType").contains("MUSIC_EXPLICIT_BADGE")
        )
    }

    func playlistItemThumbnails(from renderer: JSONValue, videoId: String) -> [Thumbnail] {
        let resolved = thumbnails(from: renderer["thumbnail"])
            + thumbnails(from: renderer.value(at: ["thumbnail", "thumbnails"]))
            + thumbnails(from: renderer.value(at: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
            + thumbnails(from: renderer.value(at: ["thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
            + thumbnails(from: renderer.value(at: ["album", "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
            + thumbnails(from: renderer.value(at: ["album", "thumbnail", "thumbnails"]))
        return (resolved + fallbackTrackThumbnails(videoId: videoId)).uniquedBy(\.url)
    }

    func mapPlayerFormat(_ value: JSONValue) -> PlayerFormat? {
        guard let itag = value["itag"]?.int,
              let mimeType = value["mimeType"]?.string
        else { return nil }
        return PlayerFormat(
            itag: itag,
            url: value["url"]?.string.flatMap(URL.init(string:)),
            mimeType: mimeType,
            bitrate: value["bitrate"]?.int ?? 0,
            contentLength: value["contentLength"]?.int,
            quality: value["quality"]?.string,
            audioQuality: value["audioQuality"]?.string
        )
    }

    func text(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let simple = value["simpleText"]?.string {
            return simple
        }
        if let text = value["text"]?.string {
            return text
        }
        let runs = value["runs"]?.array ?? value.array
        let joined = runs.compactMap { $0["text"]?.string }.joined()
        return joined.isEmpty ? value.string : joined
    }

    func thumbnails(from value: JSONValue?) -> [Thumbnail] {
        guard let value else { return [] }
        let array = value.array.isEmpty ? value.collectObjects(named: "thumbnails").flatMap(\.array) : value.array
        return array.compactMap { item in
            guard let urlString = item["url"]?.string,
                  let url = URL(string: upgradedThumbnailURLString(from: urlString))
            else { return nil }
            return Thumbnail(url: url, width: item["width"]?.int, height: item["height"]?.int)
        }
        .uniquedBy(\.url)
    }

    private func upgradedThumbnailURLString(from urlString: String) -> String {
        let pattern = #"=w\d+-h\d+[^/?#]*$"#
        if let range = urlString.range(of: pattern, options: .regularExpression) {
            return urlString.replacingCharacters(in: range, with: "=w1200-h1200-l90-rj")
        }
        if urlString.contains("ytimg.com"), urlString.contains("/vi/") {
            return urlString.replacingOccurrences(of: "hqdefault.jpg", with: "hq720.jpg")
        }
        return urlString
    }

    func headerTitle(from value: JSONValue) -> String? {
        let headerKeys = [
            "musicImmersiveHeaderRenderer",
            "musicResponsiveHeaderRenderer",
            "musicDetailHeaderRenderer",
            "musicEditablePlaylistDetailHeaderRenderer",
            "musicVisualHeaderRenderer"
        ]
        for key in headerKeys {
            for header in value.collectObjects(named: key) {
                if let title = text(from: header["title"]) {
                    return title
                }
            }
        }
        return nil
    }

    func headerThumbnails(from value: JSONValue) -> [Thumbnail] {
        let headers = ["musicImmersiveHeaderRenderer", "musicResponsiveHeaderRenderer", "musicDetailHeaderRenderer", "musicEditablePlaylistDetailHeaderRenderer", "musicVisualHeaderRenderer"]
        for key in headers {
            for header in value.collectObjects(named: key) {
                let found = thumbnails(from: header["thumbnail"])
                    + thumbnails(from: header.value(at: ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
                    + thumbnails(from: header.value(at: ["foregroundThumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
                if !found.isEmpty { return found.uniquedBy(\.url) }
            }
        }
        return thumbnails(from: value.collectObjects(named: "thumbnail").first)
    }

    func firstYear(in value: JSONValue) -> Int? {
        value.collectStrings(named: "text").compactMap(Int.init).first { $0 > 1900 && $0 < 2100 }
    }

    func firstByline(in value: JSONValue) -> String? {
        value.collectObjects(named: "subtitle")
            .compactMap { subtitle -> String? in
                playlistAuthor(from: splitRuns(subtitle["runs"]?.array ?? []), subtitle: text(from: subtitle) ?? "")
            }
            .first
    }

    func headerArtists(from value: JSONValue, title: String) -> [Artist] {
        let subtitle = headerSubtitle(from: value)
        let runs = headerSubtitleRuns(from: value)
        let titleKey = stableId(title)
        let artists = artists(from: runs, subtitle: subtitle)
            .filter { stableId($0.name) != titleKey }
            .uniquedBy(\.id)
        if !artists.isEmpty {
            return artists
        }
        return subtitleArtists(from: subtitle)
            .filter { stableId($0.name) != titleKey }
            .uniquedBy(\.id)
    }

    struct TextRun {
        var text: String
        var browseId: String?
        var pageType: String?
    }

    func splitRuns(_ runs: [JSONValue]) -> [TextRun] {
        runs.compactMap { run in
            guard let text = run["text"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty,
                  text != "•",
                  text != "·",
                  text != "-"
            else { return nil }
            let browseId = run.value(at: ["navigationEndpoint", "browseEndpoint", "browseId"])?.string
            let pageType = run.value(at: ["navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType"])?.string
            return TextRun(text: text, browseId: browseId, pageType: pageType)
        }
    }

    func headerSubtitle(from value: JSONValue) -> String {
        for header in headerObjects(in: value) {
            let candidates = [
                text(from: header["subtitle"]),
                text(from: header["straplineTextOne"]),
                text(from: header["straplineTextTwo"]),
                text(from: header["secondSubtitle"])
            ]
            if let subtitle = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) {
                return subtitle
            }
        }
        return firstByline(in: value) ?? ""
    }

    func headerSubtitleRuns(from value: JSONValue) -> [TextRun] {
        for header in headerObjects(in: value) {
            let candidates = [
                header.value(at: ["subtitle", "runs"])?.array,
                header.value(at: ["straplineTextOne", "runs"])?.array,
                header.value(at: ["straplineTextTwo", "runs"])?.array,
                header.value(at: ["secondSubtitle", "runs"])?.array
            ]
            if let runs = candidates.compactMap({ $0 }).first, !runs.isEmpty {
                return splitRuns(runs)
            }
        }
        return []
    }

    func headerObjects(in value: JSONValue) -> [JSONValue] {
        [
            "musicImmersiveHeaderRenderer",
            "musicResponsiveHeaderRenderer",
            "musicDetailHeaderRenderer",
            "musicEditablePlaylistDetailHeaderRenderer",
            "musicVisualHeaderRenderer"
        ]
        .flatMap { value.collectObjects(named: $0) }
    }

    func artists(from runs: [TextRun], subtitle: String) -> [Artist] {
        let candidates = runs.filter { $0.pageType?.contains("ARTIST") == true || $0.browseId?.hasPrefix("UC") == true }
        let selected = candidates.isEmpty ? Array(runs.prefix(1)).filter { !parseDuration($0.text).isSome && !$0.text.musicGlassIsGenericMusicRoleLabel } : candidates
        let mapped = selected.map { Artist(id: $0.browseId ?? stableId($0.text), browseId: $0.browseId, name: $0.text) }.uniquedBy(\.id)
        if !mapped.isEmpty {
            return mapped
        }
        return subtitleArtists(from: subtitle)
    }

    func album(from runs: [TextRun]) -> Album? {
        guard let run = runs.first(where: { $0.pageType?.contains("ALBUM") == true }) else { return nil }
        return Album(id: run.browseId ?? stableId(run.text), browseId: run.browseId, title: run.text)
    }

    func playlistAuthor(from runs: [TextRun], subtitle: String) -> String? {
        let runTexts = runs.map(\.text)
        let subtitleTexts = subtitle
            .components(separatedBy: CharacterSet(charactersIn: "•·"))
            .flatMap { $0.components(separatedBy: " - ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return (runTexts + subtitleTexts).first { text in
            let normalized = text.musicGlassFolded
            return !normalized.isEmpty &&
                parseDuration(text) == nil &&
                Int(text) == nil &&
                !normalized.hasSuffix(" songs") &&
                !normalized.hasSuffix(" titres") &&
                !normalized.hasSuffix(" morceaux") &&
                !normalized.hasSuffix(" videos") &&
                !["playlist", "playlists", "album", "single", "ep", "song", "songs", "video", "videos", "artist", "artiste"].contains(normalized)
        }
    }

    func trackCount(from runs: [TextRun], subtitle: String) -> Int? {
        let candidates = (runs.map(\.text) + subtitle.components(separatedBy: CharacterSet(charactersIn: "•·")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for candidate in candidates {
            let folded = candidate.musicGlassFolded
                .replacingOccurrences(of: "\u{00a0}", with: " ")
                .replacingOccurrences(of: "\u{202f}", with: " ")
            guard folded.contains("titre") || folded.contains("morceau") || folded.contains("song") || folded.contains("video") else {
                continue
            }
            let digits = folded
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .joined()
            if let count = Int(digits) {
                return count
            }
        }
        return nil
    }

    func parseDuration(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":").compactMap { TimeInterval($0) }
        guard parts.count >= 2, parts.count <= 3 else { return nil }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    func isLikelyMusicVideo(_ renderer: JSONValue) -> Bool {
        renderer.collectStrings(named: "musicVideoType").contains { $0.contains("OMV") || $0.contains("UGC") }
    }

    func stableId(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    func subtitleArtists(from subtitle: String) -> [Artist] {
        subtitle
            .components(separatedBy: CharacterSet(charactersIn: "•·"))
            .flatMap { $0.components(separatedBy: ",") }
            .flatMap { $0.components(separatedBy: " et ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { text in
                !text.isEmpty &&
                parseDuration(text) == nil &&
                Int(text) == nil &&
                !text.localizedCaseInsensitiveContains("vue") &&
                !text.localizedCaseInsensitiveContains("views") &&
                !text.localizedCaseInsensitiveContains("song") &&
                !text.localizedCaseInsensitiveContains("morceau") &&
                !text.localizedCaseInsensitiveContains("album") &&
                !text.localizedCaseInsensitiveContains("playlist") &&
                !text.musicGlassIsGenericMusicRoleLabel
            }
            .map { Artist(id: stableId($0), name: $0) }
            .uniquedBy(\.id)
    }

    func fallbackTrackThumbnails(videoId: String) -> [Thumbnail] {
        [
            Thumbnail(url: URL(string: "https://i.ytimg.com/vi/\(videoId)/sddefault.jpg")!, width: 640, height: 480),
            Thumbnail(url: URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")!, width: 480, height: 360)
        ]
    }
}

private extension JSONValue {
    var firstFlexColumnText: JSONValue? {
        array.first?["musicResponsiveListItemFlexColumnRenderer"]?["text"]
    }
}

private extension String {
    func removePrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    var musicGlassFolded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var musicGlassIsGenericMusicRoleLabel: Bool {
        [
            "album",
            "single",
            "ep",
            "song",
            "songs",
            "titre",
            "titres",
            "morceau",
            "morceaux",
            "video",
            "videos",
            "artist",
            "artiste",
            "playlist",
            "playlists"
        ].contains(musicGlassFolded)
    }

    var hasMusicGlassBlockedPlayableSignal: Bool {
        contains("podcast") ||
            contains("episode") ||
            contains("non_music_audio") ||
            contains("non music audio") ||
            contains("audiobook") ||
            contains("livre audio")
    }
}

private extension Playlist {
    var musicGlassIsVisibleYouTubeMusicLibraryPlaylist: Bool {
        if browseId == "VLLM" || id == "LM" {
            return true
        }
        let folded = ([title, author ?? "", description ?? ""]).joined(separator: " ").musicGlassFolded
        guard !folded.hasMusicGlassBlockedPlayableSignal else { return false }
        guard !folded.contains("pour plus tard") else { return false }
        if let trackCount {
            return trackCount > 0
        }
        return true
    }
}

private extension Optional {
    var isSome: Bool { self != nil }
}

private extension Array {
    func ifEmpty(_ fallback: [Element]) -> [Element] {
        isEmpty ? fallback : self
    }
}
