package com.musicglass.app.youtubemusic

import org.json.JSONArray
import org.json.JSONObject

class InnerTubeJSONMapper {

    fun mapHomeFeed(jsonString: String): List<HomeSection> {
        val root = try {
            JSONObject(jsonString)
        } catch (e: Exception) {
            return emptyList()
        }

        val sections = mutableListOf<HomeSection>()
        
        val carousels = collectObjectsNamed(root, "musicCarouselShelfRenderer")
        
        for (carousel in carousels) {
            val headerText = extractText(carousel.optJSONObject("header")?.optJSONObject("musicCarouselShelfBasicHeaderRenderer")?.optJSONObject("title")) 
                ?: extractText(carousel.optJSONObject("header")?.optJSONObject("musicImmersiveCarouselShelfBasicHeaderRenderer")?.optJSONObject("title"))
                ?: "Pour vous"
                
            val contents = carousel.optJSONArray("contents") ?: JSONArray()
            val items = mutableListOf<SongItem>()
            
            for (i in 0 until contents.length()) {
                val content = contents.optJSONObject(i) ?: continue
                
                val twoRowRenderer = content.optJSONObject("musicTwoRowItemRenderer")
                if (twoRowRenderer != null) {
                    val item = mapTwoRowRenderer(twoRowRenderer)
                    if (item != null) items.add(item)
                    continue
                }
                
                val responsiveRenderer = content.optJSONObject("musicResponsiveListItemRenderer")
                if (responsiveRenderer != null) {
                    val item = mapResponsiveRenderer(responsiveRenderer)
                    if (item != null) items.add(item)
                }
            }
            
            if (items.isNotEmpty()) {
                sections.add(HomeSection(title = headerText, items = items))
            }
        }
        
        // 2. Shelf Renderers
        val shelves = collectObjectsNamed(root, "musicShelfRenderer")
        for (shelf in shelves) {
            val headerText = extractText(shelf.optJSONObject("title")) ?: "Suggestions"
            val contents = shelf.optJSONArray("contents") ?: JSONArray()
            val items = mutableListOf<SongItem>()
            
            for (i in 0 until contents.length()) {
                val content = contents.optJSONObject(i) ?: continue
                val responsiveRenderer = content.optJSONObject("musicResponsiveListItemRenderer")
                if (responsiveRenderer != null) {
                    val item = mapResponsiveRenderer(responsiveRenderer)
                    if (item != null) items.add(item)
                }
            }
            if (items.isNotEmpty()) {
                sections.add(HomeSection(title = headerText, items = items))
            }
        }

        // 3. Grid Renderers
        val grids = collectObjectsNamed(root, "gridRenderer")
        for (grid in grids) {
            val itemsArray = grid.optJSONArray("items") ?: grid.optJSONArray("contents") ?: JSONArray()
            val items = mutableListOf<SongItem>()
            for (i in 0 until itemsArray.length()) {
                val itemObj = itemsArray.optJSONObject(i) ?: continue
                val twoRowRenderer = itemObj.optJSONObject("musicTwoRowItemRenderer")
                if (twoRowRenderer != null) {
                    val item = mapTwoRowRenderer(twoRowRenderer)
                    if (item != null) items.add(item)
                }
            }
            if (items.isNotEmpty()) {
                sections.add(HomeSection(title = "Recommandations", items = items))
            }
        }
        
        return sections
    }

    private fun mapTwoRowRenderer(renderer: JSONObject): SongItem? {
        val title = extractText(renderer.optJSONObject("title")) ?: return null
        val subtitle = extractText(renderer.optJSONObject("subtitle")) ?: ""
        
        val directVideoId = renderer.optJSONObject("navigationEndpoint")
            ?.optJSONObject("watchEndpoint")
            ?.optString("videoId")
            ?.takeIf { it.isNotBlank() }
            
        val navigationBrowseId = renderer.optJSONObject("navigationEndpoint")
            ?.optJSONObject("browseEndpoint")
            ?.optString("browseId")
            ?.takeIf { it.isNotBlank() }
        val navigationPageType = renderer.optJSONObject("navigationEndpoint")
            ?.optJSONObject("browseEndpoint")
            ?.optJSONObject("browseEndpointContextSupportedConfigs")
            ?.optJSONObject("browseEndpointContextMusicConfig")
            ?.optString("pageType")
            ?.takeIf { it.isNotBlank() }
        val browseId = navigationBrowseId ?: if (directVideoId == null) firstStringNamed(renderer, "browseId") else null
        val pageType = navigationPageType ?: if (directVideoId == null) firstStringNamed(renderer, "pageType") else null
            
        val thumbnailsArray = renderer.optJSONObject("thumbnailRenderer")
            ?.optJSONObject("musicThumbnailRenderer")
            ?.optJSONObject("thumbnail")
            ?.optJSONArray("thumbnails") 
            ?: renderer.optJSONObject("thumbnail")?.optJSONArray("thumbnails")
            
        val thumbnails = parseThumbnails(thumbnailsArray)

        if (directVideoId != null && directVideoId.isNotEmpty()) {
            return SongItem(
                id = directVideoId,
                type = ItemType.SONG,
                title = title,
                artists = listOf(ArtistInfo(name = subtitle.sanitizeSubtitle())),
                album = null,
                thumbnails = thumbnails,
                durationSeconds = parseDurationFromText(subtitle)
            )
        }
        
        if (browseId != null && browseId.isNotEmpty()) {
            val type = if (pageType?.contains("ARTIST") == true || browseId.startsWith("UC")) ItemType.ARTIST
                       else if (
                           pageType?.contains("PLAYLIST") == true ||
                           browseId.startsWith("VL") ||
                           browseId.startsWith("PL") ||
                           subtitle.lowercase().contains("playlist")
                       ) ItemType.PLAYLIST
                       else if (pageType?.contains("ALBUM") == true || subtitle.lowercase().contains("album")) ItemType.ALBUM
                       else ItemType.ALBUM

            val finalId = if (type == ItemType.PLAYLIST && browseId.startsWith("VL")) browseId.substring(2) else browseId

            return SongItem(
                id = finalId,
                type = type,
                title = title,
                artists = listOf(ArtistInfo(name = subtitle.sanitizeSubtitle())),
                album = null,
                thumbnails = thumbnails,
                browseId = browseId
            )
        }

        val fallbackVideoId = firstStringNamed(renderer, "videoId")
        if (!fallbackVideoId.isNullOrBlank()) {
            return SongItem(
                id = fallbackVideoId,
                type = ItemType.SONG,
                title = title,
                artists = listOf(ArtistInfo(name = subtitle.sanitizeSubtitle())),
                album = null,
                thumbnails = thumbnails,
                durationSeconds = parseDurationFromText(subtitle)
            )
        }

        return null
    }

    private fun mapResponsiveRenderer(renderer: JSONObject): SongItem? {
        val titleObj = renderer.optJSONArray("flexColumns")?.optJSONObject(0)
            ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")?.optJSONObject("text")
        val title = extractText(titleObj)
            ?: extractText(renderer.optJSONObject("title"))
            ?: return null
        
        val subtitleObj = renderer.optJSONArray("flexColumns")?.optJSONObject(1)
            ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")?.optJSONObject("text")
            ?: renderer.optJSONObject("subtitle")
            ?: renderer.optJSONObject("longBylineText")
            ?: renderer.optJSONObject("shortBylineText")
        val subtitle = extractText(subtitleObj) ?: ""
        val subtitleRuns = subtitleObj?.optJSONArray("runs")

        val directVideoId = renderer.optJSONObject("playlistItemData")?.optString("videoId")
            ?.takeIf { it.isNotBlank() }
            ?: renderer.optJSONObject("overlay")
                ?.optJSONObject("musicItemThumbnailOverlayRenderer")
                ?.optJSONObject("content")
                ?.optJSONObject("musicPlayButtonRenderer")
                ?.optJSONObject("playNavigationEndpoint")
                ?.optJSONObject("watchEndpoint")
                ?.optString("videoId")
                ?.takeIf { it.isNotBlank() }
            ?: renderer.optJSONObject("navigationEndpoint")?.optJSONObject("watchEndpoint")?.optString("videoId")
                ?.takeIf { it.isNotBlank() }
            
        val navigationBrowseId = renderer.optJSONObject("navigationEndpoint")
            ?.optJSONObject("browseEndpoint")
            ?.optString("browseId")
            ?.takeIf { it.isNotBlank() }
        val navigationPageType = renderer.optJSONObject("navigationEndpoint")
            ?.optJSONObject("browseEndpoint")
            ?.optJSONObject("browseEndpointContextSupportedConfigs")
            ?.optJSONObject("browseEndpointContextMusicConfig")
            ?.optString("pageType")
            ?.takeIf { it.isNotBlank() }
        val browseId = navigationBrowseId ?: if (directVideoId == null) firstStringNamed(renderer, "browseId") else null
        val pageType = navigationPageType ?: if (directVideoId == null) firstStringNamed(renderer, "pageType") else null

        val thumbnailsArray = renderer.optJSONObject("thumbnail")
            ?.optJSONObject("musicThumbnailRenderer")
            ?.optJSONObject("thumbnail")
            ?.optJSONArray("thumbnails")
        val fallbackThumbnailsArray = renderer.optJSONObject("thumbnail")?.optJSONArray("thumbnails")
        val thumbnails = (parseThumbnails(thumbnailsArray) + parseThumbnails(fallbackThumbnailsArray))
            .distinctBy { it.url }
        val artists = parseArtistsFromRuns(subtitleRuns, subtitle)
        val album = parseAlbumFromRuns(subtitleRuns)
        val duration = parseDurationFromRuns(subtitleRuns) ?: parseDurationFromText(subtitle)

        if (directVideoId != null && directVideoId.isNotEmpty()) {
            return SongItem(
                id = directVideoId,
                type = ItemType.SONG,
                title = title,
                artists = artists,
                album = album,
                thumbnails = thumbnails,
                durationSeconds = duration
            )
        }
        
        if (browseId != null && browseId.isNotEmpty()) {
            val type = if (pageType?.contains("ARTIST") == true || browseId.startsWith("UC")) ItemType.ARTIST
                       else if (
                           pageType?.contains("PLAYLIST") == true ||
                           browseId.startsWith("VL") ||
                           browseId.startsWith("PL") ||
                           subtitle.lowercase().contains("playlist")
                       ) ItemType.PLAYLIST
                       else if (pageType?.contains("ALBUM") == true || subtitle.lowercase().contains("album")) ItemType.ALBUM
                       else ItemType.ALBUM

            val finalId = if (type == ItemType.PLAYLIST && browseId.startsWith("VL")) browseId.substring(2) else browseId

            return SongItem(
                id = finalId,
                type = type,
                title = title,
                artists = artists,
                album = album,
                thumbnails = thumbnails,
                browseId = browseId
            )
        }

        val fallbackVideoId = firstStringNamed(renderer, "videoId")
        if (!fallbackVideoId.isNullOrBlank()) {
            return SongItem(
                id = fallbackVideoId,
                type = ItemType.SONG,
                title = title,
                artists = artists,
                album = album,
                thumbnails = thumbnails,
                durationSeconds = duration
            )
        }
        
        return null
    }

    private fun extractText(textObj: JSONObject?): String? {
        if (textObj == null) return null
        if (textObj.has("simpleText")) {
            return textObj.optString("simpleText")
        }
        if (textObj.has("text")) {
            return textObj.optString("text")
        }
        val runs = textObj.optJSONArray("runs")
        if (runs != null) {
            val builder = StringBuilder()
            for (i in 0 until runs.length()) {
                val run = runs.optJSONObject(i)
                run?.optString("text")?.let { builder.append(it) }
            }
            return builder.toString()
        }
        return null
    }

    private fun parseArtistsFromRuns(runs: JSONArray?, subtitle: String): List<ArtistInfo> {
        val artists = mutableListOf<ArtistInfo>()

        if (runs != null) {
            for (i in 0 until runs.length()) {
                val run = runs.optJSONObject(i) ?: continue
                val text = run.optString("text").trim()
                if (text.isEmpty() || text == "•" || text == "·") continue

                val browseEndpoint = run.optJSONObject("navigationEndpoint")
                    ?.optJSONObject("browseEndpoint")
                val browseId = browseEndpoint?.optString("browseId")
                val pageType = browseEndpoint
                    ?.optJSONObject("browseEndpointContextSupportedConfigs")
                    ?.optJSONObject("browseEndpointContextMusicConfig")
                    ?.optString("pageType")

                if ((pageType?.contains("ARTIST") == true || browseId?.startsWith("UC") == true) &&
                    artists.none { it.name.equals(text, ignoreCase = true) }
                ) {
                    artists.add(ArtistInfo(name = text, browseId = browseId))
                }
            }
        }

        if (artists.isNotEmpty()) return artists

        return subtitle.split("•", "·")
            .firstOrNull()
            .orEmpty()
            .replace(" et ", ",")
            .replace("&", ",")
            .split(",")
            .map { it.trim() }
            .filter { it.isNotEmpty() && parseDuration(it) == null && !it.isGenericMusicRoleLabel() }
            .map { ArtistInfo(name = it.sanitizeSubtitle()) }
    }

    private fun String.sanitizeSubtitle(): String {
        return this.replace(Regex("(?i)\\s*[•·-]?\\s*\\d+[.,KM]*\\s*(views|vues|écoutes|plays).*"), "").trim()
    }

    private fun String.isGenericMusicRoleLabel(): Boolean {
        return trim().lowercase() in setOf(
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
        )
    }

    private fun parseAlbumFromRuns(runs: JSONArray?): AlbumInfo? {
        if (runs == null) return null

        for (i in 0 until runs.length()) {
            val run = runs.optJSONObject(i) ?: continue
            val text = run.optString("text").trim()
            if (text.isEmpty() || text == "•" || text == "·" || parseDuration(text) != null) continue

            val browseEndpoint = run.optJSONObject("navigationEndpoint")
                ?.optJSONObject("browseEndpoint")
            val browseId = browseEndpoint?.optString("browseId")
            val pageType = browseEndpoint
                ?.optJSONObject("browseEndpointContextSupportedConfigs")
                ?.optJSONObject("browseEndpointContextMusicConfig")
                ?.optString("pageType")

            if (pageType?.contains("ALBUM") == true ||
                browseId?.startsWith("MPRE") == true ||
                browseId?.startsWith("OLAK") == true
            ) {
                return AlbumInfo(name = text, browseId = browseId)
            }
        }

        return null
    }

    private fun parseDuration(text: String): Long? {
        val parts = text.trim().split(":")
        if (parts.size !in 2..3) return null

        val values = parts.map { it.toLongOrNull() ?: return null }
        return when (values.size) {
            2 -> values[0] * 60 + values[1]
            3 -> values[0] * 3600 + values[1] * 60 + values[2]
            else -> null
        }
    }

    private fun parseDurationFromRuns(runs: JSONArray?): Long? {
        if (runs == null) return null
        for (i in 0 until runs.length()) {
            val text = runs.optJSONObject(i)?.optString("text")?.trim().orEmpty()
            parseDuration(text)?.let { return it }
        }
        return null
    }

    private fun parseDurationFromText(text: String): Long? {
        return text
            .split("•", "·")
            .map { it.trim() }
            .firstNotNullOfOrNull { parseDuration(it) }
    }

    private fun parseThumbnails(array: JSONArray?): List<Thumbnail> {
        if (array == null) return emptyList()
        val list = mutableListOf<Thumbnail>()
        for (i in 0 until array.length()) {
            val item = array.optJSONObject(i) ?: continue
            val url = item.optString("url")
            val w = item.optInt("width")
            val h = item.optInt("height")
            if (url.isNotEmpty()) {
                // Upgrade thumbnail to high quality like in iOS
                var finalUrl = url
                if (finalUrl.contains("=w")) {
                    finalUrl = finalUrl.replace(Regex("=w\\d+-h\\d+[^/?#]*$"), "=w1200-h1200-l90-rj")
                }
                list.add(Thumbnail(url = finalUrl, width = w, height = h))
            }
        }
        return list
    }

    private fun collectObjectsNamed(root: Any?, keyToFind: String): List<JSONObject> {
        val results = mutableListOf<JSONObject>()
        fun traverse(node: Any?) {
            when (node) {
                is JSONObject -> {
                    if (node.has(keyToFind)) {
                        val found = node.optJSONObject(keyToFind)
                        if (found != null) results.add(found)
                    }
                    val keys = node.keys()
                    while (keys.hasNext()) {
                        traverse(node.opt(keys.next()))
                    }
                }
                is JSONArray -> {
                    for (i in 0 until node.length()) {
                        traverse(node.opt(i))
                    }
                }
            }
        }
        traverse(root)
        return results
    }

    private fun firstStringNamed(root: Any?, keyToFind: String): String? {
        fun traverse(node: Any?): String? {
            return when (node) {
                is JSONObject -> {
                    val direct = node.optString(keyToFind, "").takeIf { it.isNotBlank() }
                    if (direct != null) {
                        direct
                    } else {
                        val keys = node.keys()
                        var found: String? = null
                        while (keys.hasNext() && found == null) {
                            found = traverse(node.opt(keys.next()))
                        }
                        found
                    }
                }
                is JSONArray -> {
                    var found: String? = null
                    for (i in 0 until node.length()) {
                        found = traverse(node.opt(i))
                        if (found != null) break
                    }
                    found
                }
                else -> null
            }
        }
        return traverse(root)
    }

    private fun parsePlaylistVideoRenderer(renderer: JSONObject): SongItem? {
        val videoId = renderer.optString("videoId").takeIf { it.isNotBlank() } ?: return null
        val title = extractText(renderer.optJSONObject("title")) ?: return null
        val subtitleObj = renderer.optJSONObject("longBylineText")
            ?: renderer.optJSONObject("shortBylineText")
            ?: renderer.optJSONObject("ownerText")
        val subtitle = extractText(subtitleObj) ?: ""
        val thumbnails = parseThumbnails(renderer.optJSONObject("thumbnail")?.optJSONArray("thumbnails"))
        return SongItem(
            id = videoId,
            type = ItemType.SONG,
            title = title,
            artists = parseArtistsFromRuns(subtitleObj?.optJSONArray("runs"), subtitle),
            album = parseAlbumFromRuns(subtitleObj?.optJSONArray("runs")),
            thumbnails = thumbnails,
            durationSeconds = parseDurationFromRuns(subtitleObj?.optJSONArray("runs")) ?: parseDurationFromText(subtitle)
        )
    }

    private fun parsePlainVideoRenderer(renderer: JSONObject): SongItem? {
        val videoId = renderer.optString("videoId").takeIf { it.isNotBlank() } ?: return null
        val title = extractText(renderer.optJSONObject("title"))?.trim()?.takeIf { it.isNotBlank() } ?: return null
        val subtitleObj = renderer.optJSONObject("longBylineText")
            ?: renderer.optJSONObject("shortBylineText")
            ?: renderer.optJSONObject("ownerText")
        val subtitle = extractText(subtitleObj) ?: ""
        val thumbnails = (
            parseThumbnails(renderer.optJSONObject("thumbnail")?.optJSONArray("thumbnails")) +
                fallbackTrackThumbnails(videoId)
            ).distinctBy { it.url }

        return SongItem(
            id = videoId,
            type = ItemType.SONG,
            title = title,
            artists = parseArtistsFromRuns(subtitleObj?.optJSONArray("runs"), subtitle),
            album = parseAlbumFromRuns(subtitleObj?.optJSONArray("runs")),
            thumbnails = thumbnails,
            durationSeconds = parseDurationFromRuns(subtitleObj?.optJSONArray("runs")) ?: parseDurationFromText(subtitle)
        )
    }

    private fun parsePlaylistPanelVideoRenderer(renderer: JSONObject): SongItem? {
        val videoId = renderer.optString("videoId").takeIf { it.isNotBlank() } ?: return null
        val title = extractText(renderer.optJSONObject("title"))?.trim()?.takeIf { it.isNotBlank() } ?: return null
        val subtitleObj = renderer.optJSONObject("longBylineText")
            ?: renderer.optJSONObject("shortBylineText")
        val subtitle = extractText(subtitleObj) ?: ""
        val thumbnails = (
            parseThumbnails(renderer.optJSONObject("thumbnail")?.optJSONArray("thumbnails")) +
                parseThumbnails(
                    renderer.optJSONObject("thumbnail")
                        ?.optJSONObject("musicThumbnailRenderer")
                        ?.optJSONObject("thumbnail")
                        ?.optJSONArray("thumbnails")
                ) +
                fallbackTrackThumbnails(videoId)
            ).distinctBy { it.url }

        return SongItem(
            id = videoId,
            type = ItemType.SONG,
            title = title,
            artists = parseArtistsFromRuns(subtitleObj?.optJSONArray("runs"), subtitle),
            album = parseAlbumFromRuns(subtitleObj?.optJSONArray("runs")),
            thumbnails = thumbnails,
            durationSeconds = parseDurationFromRuns(subtitleObj?.optJSONArray("runs")) ?: parseDurationFromText(subtitle)
        )
    }

    private fun fallbackTrackThumbnails(videoId: String): List<Thumbnail> = listOf(
        Thumbnail(url = "https://i.ytimg.com/vi/$videoId/sddefault.jpg", width = 640, height = 480),
        Thumbnail(url = "https://i.ytimg.com/vi/$videoId/hqdefault.jpg", width = 480, height = 360)
    )

    fun mapLikedSongs(jsonString: String): List<SongItem> = mapLibraryTracks(jsonString)

    fun mapYTHistory(jsonString: String): List<SongItem> = mapLibraryTracks(jsonString)

    fun mapNextTracks(jsonString: String): List<SongItem> {
        val root = try {
            JSONObject(jsonString)
        } catch (e: Exception) {
            return emptyList()
        }

        return collectObjectsNamed(root, "playlistPanelVideoRenderer")
            .mapNotNull { parsePlaylistPanelVideoRenderer(it) }
            .distinctBy { it.id }
    }

    fun mapLibraryTracks(jsonString: String): List<SongItem> {
        val root = try {
            JSONObject(jsonString)
        } catch (e: Exception) {
            return emptyList()
        }

        val items = mutableListOf<SongItem>()
        collectObjectsNamed(root, "musicResponsiveListItemRenderer")
            .mapNotNullTo(items) { mapResponsiveRenderer(it) }
        collectObjectsNamed(root, "playlistVideoRenderer")
            .mapNotNullTo(items) { parsePlaylistVideoRenderer(it) }

        return items
            .filter { it.type == ItemType.SONG }
            .distinctBy { it.id }
    }

    fun mapUserPlaylists(jsonString: String): List<SongItem> {
        val root = try {
            JSONObject(jsonString)
        } catch (e: Exception) {
            return emptyList()
        }

        val gridItems = collectObjectsNamed(root, "musicTwoRowItemRenderer")
            .mapNotNull { mapTwoRowRenderer(it) }
            .filter { it.type == ItemType.PLAYLIST }

        val listItems = collectObjectsNamed(root, "musicResponsiveListItemRenderer")
            .mapNotNull { mapResponsiveRenderer(it) }
            .filter { it.type == ItemType.PLAYLIST }

        return (gridItems + listItems)
            .filterNot { it.title.equals("YouTube Music", ignoreCase = true) }
            .distinctBy { it.id }
    }

    fun mapPlayerPayload(jsonString: String, videoId: String): PlayerPayload? {
        val root = try {
            JSONObject(jsonString)
        } catch (e: Exception) {
            return null
        }

        val playabilityStatus = root.optJSONObject("playabilityStatus")?.optString("status") ?: "UNKNOWN"
        val reason = root.optJSONObject("playabilityStatus")?.optString("reason")
        val videoDetails = root.optJSONObject("videoDetails")

        val title = videoDetails?.optString("title")?.takeIf { it.isNotBlank() } ?: "Titre inconnu"
        val author = videoDetails?.optString("author")
        val durationSeconds = videoDetails?.optString("lengthSeconds")?.toLongOrNull()
        
        val thumbnailsArray = videoDetails?.optJSONObject("thumbnail")?.optJSONArray("thumbnails")
        val thumbnails = parseThumbnails(thumbnailsArray)

        val streamingData = root.optJSONObject("streamingData")
        val hlsManifestUrl = streamingData?.optString("hlsManifestUrl")
        val serverAbrStreamingUrl = streamingData?.optString("serverAbrStreamingUrl")

        // Some payloads expose URLs in "adaptiveFormats", others in "formats".
        val formatsArray = JSONArray().apply {
            val adaptiveFormats = streamingData?.optJSONArray("adaptiveFormats") ?: JSONArray()
            for (i in 0 until adaptiveFormats.length()) {
                put(adaptiveFormats.opt(i))
            }
            val regularFormats = streamingData?.optJSONArray("formats") ?: JSONArray()
            for (i in 0 until regularFormats.length()) {
                put(regularFormats.opt(i))
            }
        }
        val formats = mutableListOf<PlayerFormat>()
        for (i in 0 until formatsArray.length()) {
            val format = formatsArray.optJSONObject(i) ?: continue
            val formatUrl = format.optString("url").takeIf { it.isNotBlank() }
            // Skip formats without direct URL (they use signatureCipher which we can't decrypt)
            if (formatUrl.isNullOrEmpty()) continue
            formats.add(
                PlayerFormat(
                    itag = format.optInt("itag"),
                    url = formatUrl,
                    mimeType = format.optString("mimeType", ""),
                    bitrate = format.optInt("bitrate", 0),
                    audioQuality = format.optString("audioQuality").takeIf { it.isNotBlank() }
                )
            )
        }

        return PlayerPayload(
            videoId = videoId,
            title = title,
            author = author,
            durationSeconds = durationSeconds,
            thumbnails = thumbnails,
            formats = formats,
            playabilityStatus = playabilityStatus,
            hlsManifestUrl = hlsManifestUrl?.takeIf { it.isNotEmpty() },
            serverAbrStreamingUrl = serverAbrStreamingUrl?.takeIf { it.isNotEmpty() },
            reason = reason?.takeIf { it.isNotEmpty() }
        )
    }

    // --- Playlist / Album details ---

    /**
     * Extracts the header title from the browse response, exactly like iOS's headerTitle().
     * Searches recursively in: musicResponsiveHeaderRenderer, musicDetailHeaderRenderer,
     * musicEditablePlaylistDetailHeaderRenderer, musicVisualHeaderRenderer
     */
    private fun headerTitle(root: JSONObject): String? {
        val headerKeys = listOf(
            "musicImmersiveHeaderRenderer",
            "musicResponsiveHeaderRenderer",
            "musicDetailHeaderRenderer", 
            "musicEditablePlaylistDetailHeaderRenderer",
            "musicVisualHeaderRenderer"
        )
        for (key in headerKeys) {
            for (header in collectObjectsNamed(root, key)) {
                val title = extractText(header.optJSONObject("title"))
                if (title != null && title.isNotEmpty()) return title
            }
        }
        return null
    }

    /**
     * Extracts the header subtitle from the browse response.
     */
    private fun headerSubtitle(root: JSONObject): String? {
        val headerKeys = listOf(
            "musicImmersiveHeaderRenderer",
            "musicResponsiveHeaderRenderer",
            "musicDetailHeaderRenderer",
            "musicEditablePlaylistDetailHeaderRenderer",
            "musicVisualHeaderRenderer"
        )
        for (key in headerKeys) {
            for (header in collectObjectsNamed(root, key)) {
                val candidates = listOf(
                    extractText(header.optJSONObject("subtitle")),
                    extractText(header.optJSONObject("straplineTextOne")),
                    extractText(header.optJSONObject("straplineTextTwo")),
                    extractText(header.optJSONObject("secondSubtitle"))
                )
                val subtitle = candidates.firstOrNull { !it.isNullOrEmpty() }
                if (subtitle != null) return subtitle
            }
        }
        return null
    }

    /**
     * Extracts thumbnails from the header, searching multiple paths like iOS.
     */
    private fun headerThumbnails(root: JSONObject): List<Thumbnail> {
        val headerKeys = listOf(
            "musicImmersiveHeaderRenderer",
            "musicResponsiveHeaderRenderer",
            "musicDetailHeaderRenderer",
            "musicEditablePlaylistDetailHeaderRenderer",
            "musicVisualHeaderRenderer"
        )
        for (key in headerKeys) {
            for (header in collectObjectsNamed(root, key)) {
                // Try all possible thumbnail paths
                val paths = listOf(
                    header.optJSONObject("thumbnail")
                        ?.optJSONObject("musicThumbnailRenderer")
                        ?.optJSONObject("thumbnail")
                        ?.optJSONArray("thumbnails"),
                    header.optJSONObject("thumbnail")
                        ?.optJSONObject("croppedSquareThumbnailRenderer")
                        ?.optJSONObject("thumbnail")
                        ?.optJSONArray("thumbnails"),
                    header.optJSONObject("foregroundThumbnail")
                        ?.optJSONObject("musicThumbnailRenderer")
                        ?.optJSONObject("thumbnail")
                        ?.optJSONArray("thumbnails")
                )
                for (thumbnailArray in paths) {
                    val result = parseThumbnails(thumbnailArray)
                    if (result.isNotEmpty()) return result
                }
            }
        }
        return emptyList()
    }

    fun mapPlaylistDetails(jsonString: String, browseId: String): PlaylistDetails? {
        val root = try {
            JSONObject(jsonString)
        } catch (e: Exception) {
            return null
        }

        val title = headerTitle(root) ?: "Playlist"
        val author = headerSubtitle(root)
        val thumbnails = headerThumbnails(root)

        val tracks = mutableListOf<SongItem>()
        
        // Collect all music tracks like iOS does
        val responsiveRenderers = collectObjectsNamed(root, "musicResponsiveListItemRenderer")
        for (item in responsiveRenderers) {
            val mapped = mapResponsiveRenderer(item)
            if (mapped != null && mapped.type == ItemType.SONG) {
                tracks.add(mapped)
            }
        }

        // Also try playlistVideoRenderer (YouTube playlists)
        if (tracks.isEmpty()) {
            val playlistRenderers = collectObjectsNamed(root, "playlistVideoRenderer")
            for (renderer in playlistRenderers) {
                parsePlaylistVideoRenderer(renderer)?.let { tracks.add(it) }
            }
        }

        if (tracks.isEmpty()) {
            val videoRenderers = collectObjectsNamed(root, "videoRenderer")
            for (renderer in videoRenderers) {
                parsePlainVideoRenderer(renderer)?.let { tracks.add(it) }
            }
        }

        return PlaylistDetails(
            id = browseId,
            title = title,
            author = author,
            thumbnails = thumbnails,
            tracks = tracks.distinctBy { it.id }
        )
    }

    fun mapAlbumDetails(jsonString: String, browseId: String): PlaylistDetails? {
        val root = try {
            JSONObject(jsonString)
        } catch (e: Exception) {
            return null
        }

        val title = headerTitle(root) ?: "Album"
        val author = headerSubtitle(root)
        val thumbnails = headerThumbnails(root)
        val albumContext = AlbumInfo(name = title, browseId = browseId, thumbnails = thumbnails)

        val tracks = collectObjectsNamed(root, "musicResponsiveListItemRenderer")
            .mapNotNull { mapResponsiveRenderer(it) }
            .filter { it.type == ItemType.SONG }
            .map { track ->
                track.copy(
                    album = track.album ?: albumContext,
                    artists = track.artists.ifEmpty { author.toArtistList() }
                )
            }
            .distinctBy { it.id }

        return PlaylistDetails(
            id = browseId,
            title = title,
            author = author,
            thumbnails = thumbnails,
            tracks = tracks
        )
    }

    fun mapArtistPage(jsonString: String, browseId: String): ArtistPage? {
        val root = try {
            JSONObject(jsonString)
        } catch (e: Exception) {
            return null
        }

        val name = headerTitle(root) ?: "Artiste"
        val searchItems = mapSearchResults(jsonString)
        return ArtistPage(
            id = browseId,
            name = name,
            thumbnails = headerThumbnails(root),
            topTracks = searchItems
                .filter { it.type == ItemType.SONG }
                .distinctBy { it.id },
            albums = searchItems
                .filter { it.type == ItemType.ALBUM }
                .distinctBy { it.browseId ?: it.id }
        )
    }

    private fun String?.toArtistList(): List<ArtistInfo> {
        return this
            .orEmpty()
            .split("•")
            .firstOrNull()
            .orEmpty()
            .replace(" et ", ",")
            .replace("&", ",")
            .split(",")
            .map { it.trim() }
            .filter { it.isNotEmpty() && parseDuration(it) == null && !it.isGenericMusicRoleLabel() }
            .map { ArtistInfo(name = it) }
    }

    /**
     * Map search results to a flat list of SongItems.
     * Used by the fallback playback system to find alternative playable versions.
     */
    fun mapSearchResults(jsonString: String): List<SongItem> {
        val root = try {
            JSONObject(jsonString)
        } catch (e: Exception) {
            return emptyList()
        }

        val items = mutableListOf<SongItem>()

        // Collect from musicResponsiveListItemRenderer (search results)
        val responsiveRenderers = collectObjectsNamed(root, "musicResponsiveListItemRenderer")
        for (renderer in responsiveRenderers) {
            val mapped = mapResponsiveRenderer(renderer)
            if (mapped != null) items.add(mapped)
        }

        // Also collect from musicTwoRowItemRenderer
        val twoRowRenderers = collectObjectsNamed(root, "musicTwoRowItemRenderer")
        for (renderer in twoRowRenderers) {
            val mapped = mapTwoRowRenderer(renderer)
            if (mapped != null) items.add(mapped)
        }

        return items
    }

    fun mapSuggestions(jsonString: String): List<String> {
        val root = try {
            JSONObject(jsonString)
        } catch (e: Exception) {
            return emptyList()
        }

        return collectObjectsNamed(root, "searchSuggestionRenderer")
            .mapNotNull { renderer ->
                extractText(renderer.optJSONObject("suggestion"))
            }
            .distinct()
    }
}
