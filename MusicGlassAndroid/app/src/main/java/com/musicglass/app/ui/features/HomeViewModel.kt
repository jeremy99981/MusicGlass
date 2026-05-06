package com.musicglass.app.ui.features

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.musicglass.app.persistence.PlaybackHistoryRepository
import com.musicglass.app.youtubemusic.AuthService
import com.musicglass.app.youtubemusic.HomeSection
import com.musicglass.app.youtubemusic.InnerTubeClient
import com.musicglass.app.youtubemusic.InnerTubeJSONMapper
import com.musicglass.app.youtubemusic.ItemType
import com.musicglass.app.youtubemusic.SongItem
import com.musicglass.app.youtubemusic.cleanedMusicGlassMetadata
import com.musicglass.app.youtubemusic.isGenericMusicGlassArtistLabel
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

class HomeViewModel : ViewModel() {
    private val innerTubeClient = InnerTubeClient()
    private val mapper = InnerTubeJSONMapper()

    private val _homeFeed = MutableStateFlow<List<HomeSection>>(emptyList())
    val homeFeed: StateFlow<List<HomeSection>> = _homeFeed

    private val _isLoading = MutableStateFlow(true)
    val isLoading: StateFlow<Boolean> = _isLoading

    private var cachedYouTubeRecent: List<SongItem> = emptyList()
    private var cachedUserPlaylists: List<SongItem> = emptyList()
    private var cachedBaseSections: List<HomeSection> = emptyList()

    init {
        fetchHomeFeed()
        viewModelScope.launch {
            AuthService.state.drop(1).collect {
                fetchHomeFeed()
            }
        }
        viewModelScope.launch {
            PlaybackHistoryRepository.history.drop(1).collect {
                refreshRecentlyPlayedSection()
            }
        }
    }

    private fun fetchHomeFeed() {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val localHistory = PlaybackHistoryRepository.recentlyPlayed()

                coroutineScope {
                    val baseFeedTask = async {
                        runCatching {
                            mapper.mapHomeFeed(innerTubeClient.getHomeFeed())
                        }.getOrDefault(emptyList())
                    }
                    val discoveryTask = async { makeDiscoverySections(localHistory) }
                    val userPlaylistsTask = async {
                        if (AuthService.state.value.isAuthenticated) {
                            runCatching {
                                mapper.mapUserPlaylists(innerTubeClient.getUserPlaylists()).take(16)
                            }.getOrDefault(emptyList())
                        } else {
                            emptyList()
                        }
                    }
                    val youtubeRecentTask = async {
                        if (AuthService.state.value.isAuthenticated) {
                            runCatching {
                                mapper.mapYTHistory(innerTubeClient.getYTHistory()).take(12)
                            }.getOrDefault(emptyList())
                        } else {
                            emptyList()
                        }
                    }

                    val baseSections = baseFeedTask.await()
                    cachedBaseSections = baseSections
                    cachedUserPlaylists = userPlaylistsTask.await()
                    cachedYouTubeRecent = youtubeRecentTask.await()

                    val firstFeed = buildFeed(
                        baseSections = baseSections,
                        discoverySections = emptyList()
                    )
                    if (firstFeed.isNotEmpty()) {
                        _homeFeed.value = firstFeed
                    }

                    val finalFeed = buildFeed(
                        baseSections = baseSections,
                        discoverySections = discoveryTask.await()
                    )
                    if (finalFeed.isNotEmpty() || _homeFeed.value.isEmpty()) {
                        _homeFeed.value = finalFeed
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                _isLoading.value = false
            }
        }
    }

    private fun buildFeed(
        baseSections: List<HomeSection>,
        discoverySections: List<HomeSection>
    ): List<HomeSection> {
        val sections = mutableListOf<HomeSection>()

        // 1. Écoutés récemment
        val recent = recentlyPlayedItems(cachedYouTubeRecent)
        if (recent.isNotEmpty()) {
            sections.add(HomeSection(title = "Écoutés récemment", items = recent))
        }

        // 2. Mes playlists
        if (cachedUserPlaylists.isNotEmpty()) {
            sections.add(HomeSection(title = "Mes playlists", items = cachedUserPlaylists))
        }

        // 3. Sections de découverte personnalisées (Plus de, Dans l'univers de)
        sections.addAll(discoverySections)

        // 4. Recommandations YouTube (rap français pour toi, titres tendance, etc.)
        sections.addAll(splitPlaylistSections(baseSections))

        return sanitizeSections(sections)
    }

    private suspend fun makeDiscoverySections(history: List<SongItem>): List<HomeSection> {
        val queries = discoveryQueries(history)
        if (queries.isEmpty()) return emptyList()

        return coroutineScope {
            queries.map { query ->
                async {
                    runCatching { query.toSection() }.getOrNull()
                }
            }
                .awaitAll()
                .filterNotNull()
                .sortedBy { section -> queries.indexOfFirst { it.title == section.title } }
        }
    }

    private suspend fun HomeDiscoveryQuery.toSection(): HomeSection? {
        val collected = mutableListOf<SongItem>()

        for (query in searchQueries) {
            val json = runCatching { innerTubeClient.search(query, params = params) }.getOrNull() ?: continue
            val mapped = mapper.mapSearchResults(json)
            collected.addAll(itemsFrom(mapped))
            if (collected.distinctBy { it.stableHomeKey() }.size >= limit) break
        }

        val items = collected
            .distinctBy { it.stableHomeKey() }
            .take(limit)

        return if (items.isNotEmpty()) HomeSection(title = title, items = items) else null
    }

    private fun refreshRecentlyPlayedSection() {
        val current = _homeFeed.value.filterNot { it.title == "Écoutés récemment" }.toMutableList()
        val recent = recentlyPlayedItems(cachedYouTubeRecent)
        if (recent.isNotEmpty()) {
            current.add(0, HomeSection(title = "Écoutés récemment", items = recent))
        }
        _homeFeed.value = current

        viewModelScope.launch {
            val localHistory = PlaybackHistoryRepository.recentlyPlayed()
            val newDiscovery = makeDiscoverySections(localHistory)
            if (cachedBaseSections.isNotEmpty()) {
                val updatedFeed = buildFeed(
                    baseSections = cachedBaseSections,
                    discoverySections = newDiscovery
                )
                if (updatedFeed.isNotEmpty()) {
                    _homeFeed.value = updatedFeed
                }
            }
        }
    }

    private fun recentlyPlayedItems(youtubeRecent: List<SongItem> = emptyList()): List<SongItem> {
        return (PlaybackHistoryRepository.recentlyPlayed() + youtubeRecent)
            .map { it.cleanedMusicGlassMetadata() }
            .distinctBy { it.id }
            .filter { it.isHomeTrack() }
            .take(12)
    }

    private fun discoveryQueries(history: List<SongItem>): List<HomeDiscoveryQuery> {
        val queries = mutableListOf(
            HomeDiscoveryQuery("Titres tendance", "titres tendance France", listOf("hits du moment France", "top titres France", "nouveautés rap pop France"), SONGS_PARAMS, DiscoveryContent.TRACKS, 16),
            HomeDiscoveryQuery("Playlists officielles", "France hits", listOf("Rap Français Hits YouTube Music", "Hits 80 YouTube Music", "Hits 90 YouTube Music", "Pop Hits YouTube Music", "Nouveautés YouTube Music"), FEATURED_PLAYLISTS_PARAMS, DiscoveryContent.OFFICIAL_PLAYLISTS, 16),
            HomeDiscoveryQuery("Albums tendance", "albums tendance France", listOf("albums rap français 2026", "albums pop française 2026", "nouveaux albums France"), ALBUMS_PARAMS, DiscoveryContent.ALBUMS, 14),
            HomeDiscoveryQuery("Nouveautés à découvrir", "nouveautés musique France", listOf("nouveautés rap français", "nouveautés pop française", "sorties musique France"), SONGS_PARAMS, DiscoveryContent.TRACKS, 16),
            HomeDiscoveryQuery("Playlists communautaires", "France hits", listOf("playlist rap français", "playlist pop française", "playlist soirée France", "playlist chill français"), COMMUNITY_PLAYLISTS_PARAMS, DiscoveryContent.COMMUNITY_PLAYLISTS, 16),
            HomeDiscoveryQuery("Rap français du moment", "rap français nouveautés", emptyList(), SONGS_PARAMS, DiscoveryContent.TRACKS, 16),
            HomeDiscoveryQuery("Pop française", "pop française nouveautés", emptyList(), SONGS_PARAMS, DiscoveryContent.TRACKS, 14),
            HomeDiscoveryQuery("Officiel - pour se poser", "chill détente", listOf("Relax YouTube Music", "Chill Hits YouTube Music", "Acoustic Chill YouTube Music"), FEATURED_PLAYLISTS_PARAMS, DiscoveryContent.OFFICIAL_PLAYLISTS, 12),
            HomeDiscoveryQuery("Communauté - pour se poser", "chill détente", listOf("playlist chill détente", "playlist calme français", "playlist détente musique"), COMMUNITY_PLAYLISTS_PARAMS, DiscoveryContent.COMMUNITY_PLAYLISTS, 12),
            HomeDiscoveryQuery("Énergie week-end", "hits énergie week-end", emptyList(), SONGS_PARAMS, DiscoveryContent.TRACKS, 14)
        )

        topArtistNames(history, limit = 3).forEach { artist ->
            queries.add(HomeDiscoveryQuery("Plus de $artist", "$artist meilleurs titres", emptyList(), SONGS_PARAMS, DiscoveryContent.TRACKS, 12))
            queries.add(HomeDiscoveryQuery("Dans l’univers de $artist", "$artist radio artistes similaires", emptyList(), SONGS_PARAMS, DiscoveryContent.TRACKS, 12))
        }

        inferredThemes(history).take(4).forEach { theme ->
            queries.add(HomeDiscoveryQuery(theme.title, theme.query, emptyList(), SONGS_PARAMS, DiscoveryContent.TRACKS, 14))
        }

        return queries.distinctBy { it.title }
    }

    private fun topArtistNames(history: List<SongItem>, limit: Int): List<String> {
        return history
            .flatMap { item ->
                item.artists.map { it.name }.ifEmpty {
                    item.artistLine().split(",", "&").map { it.trim() }
                }
            }
            .filter { it.isNotBlank() && !it.contains("unknown", ignoreCase = true) }
            .groupingBy { it }
            .eachCount()
            .entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key.lowercase() })
            .take(limit)
            .map { it.key }
    }

    private fun inferredThemes(history: List<SongItem>): List<HomeTheme> {
        val listeningText = history
            .flatMap { listOf(it.title, it.artistLine(), it.album?.name.orEmpty()) }
            .joinToString(" ")
            .folded()

        val themes = listOf(
            HomeThemeMatcher(HomeTheme("Rap français pour vous", "rap français nouveautés"), listOf("plk", "ninho", "pnl", "jul", "damso", "nekfeu", "laylow", "tiakola", "gazo", "zola", "niska", "koba", "hamza", "leto", "sdm", "freeze corleone", "rap")),
            HomeThemeMatcher(HomeTheme("Pop française à explorer", "pop française nouveautés"), listOf("angele", "stromae", "clara luciani", "zaho de sagazan", "helene sio", "pomme", "louane", "vianney", "pop")),
            HomeThemeMatcher(HomeTheme("R&B et vibes douces", "rnb francais chill"), listOf("rnb", "r&b", "the weeknd", "sza", "frank ocean", "soul", "hamza", "tsew the kid")),
            HomeThemeMatcher(HomeTheme("Électro et énergie", "electro house nouveautés"), listOf("electro", "house", "techno", "daft punk", "justice", "kavinsky", "gesaffelstein", "dance")),
            HomeThemeMatcher(HomeTheme("Rock et alternatif", "rock alternatif nouveautés"), listOf("rock", "twenty one pilots", "arctic monkeys", "tame impala", "coldplay", "indie", "alternative")),
            HomeThemeMatcher(HomeTheme("Concentration et calme", "concentration chill lo-fi"), listOf("lofi", "lo-fi", "chill", "focus", "piano", "study", "sleep", "calme"))
        )

        val matched = themes
            .filter { matcher -> matcher.keywords.any { listeningText.contains(it) } }
            .map { it.theme }

        if (matched.isEmpty() && history.isNotEmpty()) {
            val seedArtists = history.take(3)
                .map { it.artistLine() }
                .filter { it.isNotBlank() }
                .joinToString(" ")
            if (seedArtists.isNotBlank()) {
                return listOf(HomeTheme("Inspiré par vos écoutes", "$seedArtists radio"))
            }
        }

        return matched
    }

    private fun splitPlaylistSections(sections: List<HomeSection>): List<HomeSection> {
        return sections.flatMap { section ->
            val nonPlaylists = section.items.filter { it.type != ItemType.PLAYLIST && it.isAllowedOnHome() }
            val officialPlaylists = section.items.filter { it.type == ItemType.PLAYLIST && it.isHomePlaylist() && it.isOfficialYouTubeMusicPlaylist() }
            val communityPlaylists = section.items.filter { it.type == ItemType.PLAYLIST && it.isHomePlaylist() && !it.isOfficialYouTubeMusicPlaylist() }

            buildList {
                if (nonPlaylists.isNotEmpty()) add(HomeSection(section.title.toFrenchHomeTitle(), nonPlaylists))
                if (officialPlaylists.isNotEmpty()) add(HomeSection("${section.title.toFrenchHomeTitle()} - officiel", officialPlaylists))
                if (communityPlaylists.isNotEmpty()) add(HomeSection("${section.title.toFrenchHomeTitle()} - communauté", communityPlaylists))
            }
        }
    }

    private fun sanitizeSections(sections: List<HomeSection>): List<HomeSection> {
        val seenTitles = mutableSetOf<String>()
        val seenItems = mutableSetOf<String>()

        return sections.mapNotNull { section ->
            if (!seenTitles.add(section.title)) return@mapNotNull null
            val items = section.items
                .map { it.cleanedMusicGlassMetadata() }
                .filter { it.isAllowedOnHome() }
                .filter { seenItems.add(it.stableHomeKey()) }
            if (items.isEmpty()) null else HomeSection(section.title, items)
        }
    }

    private data class HomeDiscoveryQuery(
        val title: String,
        val query: String,
        val fallbackQueries: List<String>,
        val params: String?,
        val content: DiscoveryContent,
        val limit: Int
    ) {
        val searchQueries: List<String>
            get() = (listOf(query) + fallbackQueries).distinct()

        fun itemsFrom(items: List<SongItem>): List<SongItem> {
            return when (content) {
                DiscoveryContent.TRACKS -> items.filter { it.isHomeTrack() }
                DiscoveryContent.OFFICIAL_PLAYLISTS -> items.filter { it.type == ItemType.PLAYLIST && it.isHomePlaylist() && it.isOfficialYouTubeMusicPlaylist() }
                DiscoveryContent.COMMUNITY_PLAYLISTS -> items.filter { it.type == ItemType.PLAYLIST && it.isHomePlaylist() && !it.isOfficialYouTubeMusicPlaylist() }
                DiscoveryContent.ALBUMS -> items.filter { it.type == ItemType.ALBUM && it.isHomeAlbum() }
            }
        }
    }

    private enum class DiscoveryContent {
        TRACKS,
        OFFICIAL_PLAYLISTS,
        COMMUNITY_PLAYLISTS,
        ALBUMS
    }

    private data class HomeTheme(val title: String, val query: String)

    private data class HomeThemeMatcher(val theme: HomeTheme, val keywords: List<String>)

    companion object {
        private const val SONGS_PARAMS = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
        private const val ALBUMS_PARAMS = "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"
        private const val FEATURED_PLAYLISTS_PARAMS = "EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D"
        private const val COMMUNITY_PLAYLISTS_PARAMS = "EgeKAQQoAEABagoQAxAEEAoQCRAF"
    }
}

private fun SongItem.isAllowedOnHome(): Boolean {
    return when (type) {
        ItemType.SONG -> isHomeTrack()
        ItemType.PLAYLIST -> isHomePlaylist()
        ItemType.ALBUM -> isHomeAlbum()
        ItemType.ARTIST -> false
    }
}

private fun SongItem.isHomeTrack(): Boolean {
    val folded = listOf(title, artistLine(), album?.name.orEmpty()).joinToString(" ").folded()
    return type == ItemType.SONG &&
        !folded.hasBlockedMusicSignal() &&
        !folded.looksLikeLongFormMusicCard() &&
        artistLine().isNotBlank()
}

private fun SongItem.isHomeAlbum(): Boolean {
    val folded = listOf(title, artistLine()).joinToString(" ").folded()
    return !folded.hasBlockedMusicSignal() && !folded.looksLikeLongFormMusicCard()
}

private fun SongItem.isHomePlaylist(): Boolean {
    val folded = listOf(title, artistLine()).joinToString(" ").folded()
    return !folded.hasBlockedMusicSignal() && !folded.looksLikePlaylistPollution()
}

private fun SongItem.isOfficialYouTubeMusicPlaylist(): Boolean {
    val author = artistLine().folded()
    val title = title.folded()
    val officialAuthors = listOf("youtube music", "youtube", "yt music", "charts")
    if (officialAuthors.any { author == it || author.contains(it) }) return true

    val officialTitleHints = listOf(
        "hits du",
        "hits de",
        "les hits",
        "top 100",
        "top france",
        "nouveautes",
        "decouvertes",
        "tendances",
        "charts"
    )
    return author.isBlank() && officialTitleHints.any { title.contains(it) }
}

private fun SongItem.artistLine(): String {
    return artists
        .map { it.name.trim() }
        .filter { it.isNotBlank() && !it.isGenericMusicGlassArtistLabel() }
        .joinToString(", ")
        .trim()
}

private fun SongItem.stableHomeKey(): String {
    return "${type.name}:${browseId ?: id}"
}

private fun String.toFrenchHomeTitle(): String {
    return when (lowercase()) {
        "recently played" -> "Écoutés récemment"
        "quick picks" -> "Suggestions rapides"
        "suggested albums" -> "Albums suggérés"
        "trending" -> "Tendances"
        "recommendations" -> "Recommandations"
        "playlists" -> "Playlists"
        else -> this
    }
}

private fun String.folded(): String {
    return java.text.Normalizer.normalize(this, java.text.Normalizer.Form.NFD)
        .replace(Regex("\\p{Mn}+"), "")
        .lowercase()
        .trim()
}

private fun String.hasBlockedMusicSignal(): Boolean {
    return contains("podcast") ||
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

private fun String.looksLikeLongFormMusicCard(): Boolean {
    return contains("1 hour") ||
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

private fun String.looksLikePlaylistPollution(): Boolean {
    return contains("1 hour") ||
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
        contains("concert complet")
}
