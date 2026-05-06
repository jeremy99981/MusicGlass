package com.musicglass.app.ui.features

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.musicglass.app.youtubemusic.ArtistPage
import com.musicglass.app.youtubemusic.ArtistInfo
import com.musicglass.app.youtubemusic.ArtworkEnricher
import com.musicglass.app.youtubemusic.InnerTubeClient
import com.musicglass.app.youtubemusic.InnerTubeJSONMapper
import com.musicglass.app.youtubemusic.ItemType
import com.musicglass.app.youtubemusic.PlaylistDetails
import com.musicglass.app.youtubemusic.SongItem
import com.musicglass.app.youtubemusic.Thumbnail
import com.musicglass.app.youtubemusic.bestThumbnailUrl
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class AlbumDetailViewModel : ViewModel() {
    private val client = InnerTubeClient()
    private val mapper = InnerTubeJSONMapper()
    private val artworkEnricher = ArtworkEnricher(client, mapper)

    private val _album = MutableStateFlow<PlaylistDetails?>(null)
    val album: StateFlow<PlaylistDetails?> = _album

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading

    private val _isRefreshingArtwork = MutableStateFlow(false)
    val isRefreshingArtwork: StateFlow<Boolean> = _isRefreshingArtwork

    fun loadAlbum(browseId: String) {
        if (_album.value?.id == browseId) return

        viewModelScope.launch {
            _isLoading.value = true
            try {
                val loaded = runCatching {
                    mapper.mapAlbumDetails(client.getBrowse(browseId), browseId)
                }.getOrNull()
                    ?: runCatching {
                        mapper.mapAlbumDetails(client.getBrowseAuthenticated(browseId), browseId)
                    }.getOrNull()

                val completed = loaded?.let { completeAlbumDetails(it) }
                _album.value = completed
                _isLoading.value = false
                if (completed != null) refreshArtwork(completed)
            } catch (e: Exception) {
                e.printStackTrace()
                _isLoading.value = false
            }
        }
    }

    private suspend fun completeAlbumDetails(details: PlaylistDetails): PlaylistDetails {
        val existingArtists = details.tracks
            .flatMap { it.artists }
            .filterUsefulAlbumArtists(details.title)

        val searchedArtists = if (existingArtists.isNotEmpty()) {
            emptyList()
        } else {
            runCatching {
                mapper.mapSearchResults(client.search("${details.title} album", params = ALBUMS_PARAMS))
                    .firstOrNull { candidate ->
                        candidate.type == ItemType.ALBUM &&
                            (
                                candidate.browseId == details.id ||
                                    candidate.id == details.id ||
                                    candidate.title.equals(details.title, ignoreCase = true)
                            )
                    }
                    ?.artists
                    .orEmpty()
                    .filterUsefulAlbumArtists(details.title)
            }.getOrDefault(emptyList())
        }

        val fallbackArtists = existingArtists
            .ifEmpty { searchedArtists }
            .distinctBy { it.name.lowercase() }
        val completedTracks = details.tracks.map { track ->
            val usefulArtists = track.artists.filterUsefulAlbumArtists(details.title)
            track.copy(artists = usefulArtists.ifEmpty { fallbackArtists })
        }

        return details.copy(
            author = details.author.withAlbumArtistLine(fallbackArtists),
            tracks = completedTracks
        )
    }

    private suspend fun refreshArtwork(loadedAlbum: PlaylistDetails) {
        if (loadedAlbum.tracks.isEmpty()) return
        _isRefreshingArtwork.value = true
        try {
            val fallbackAlbum = com.musicglass.app.youtubemusic.AlbumInfo(
                name = loadedAlbum.title,
                browseId = loadedAlbum.id,
                thumbnails = loadedAlbum.thumbnails
            )
            val visibleTracks = artworkEnricher.enrichArtwork(loadedAlbum.tracks, fallbackAlbum, limit = 18)
            updateTracks(loadedAlbum.id, visibleTracks)
            val allTracks = artworkEnricher.enrichArtwork(visibleTracks, fallbackAlbum, limit = 80)
            updateTracks(loadedAlbum.id, allTracks)
        } finally {
            _isRefreshingArtwork.value = false
        }
    }

    private fun updateTracks(albumId: String, tracks: List<SongItem>) {
        val current = _album.value ?: return
        if (current.id != albumId) return
        _album.value = current.copy(
            thumbnails = resolveAlbumThumbnails(current, tracks),
            tracks = tracks
        )
    }

    private fun resolveAlbumThumbnails(current: PlaylistDetails, tracks: List<SongItem>): List<Thumbnail> {
        return tracks.firstNotNullOfOrNull { it.album?.thumbnails?.takeIf(List<Thumbnail>::isNotEmpty) }
            ?: tracks.firstOrNull()?.thumbnails?.takeIf { it.isNotEmpty() }
            ?: current.thumbnails
    }

    private companion object {
        const val ALBUMS_PARAMS = "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"
    }
}

class ArtistDetailViewModel : ViewModel() {
    private val client = InnerTubeClient()
    private val mapper = InnerTubeJSONMapper()
    private val artworkEnricher = ArtworkEnricher(client, mapper)

    private val _page = MutableStateFlow<ArtistPage?>(null)
    val page: StateFlow<ArtistPage?> = _page

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading

    private val _isRefreshingArtwork = MutableStateFlow(false)
    val isRefreshingArtwork: StateFlow<Boolean> = _isRefreshingArtwork

    fun loadArtist(browseId: String) {
        if (_page.value?.id == browseId) return

        viewModelScope.launch {
            _isLoading.value = true
            try {
                val browsed = runCatching {
                    mapper.mapArtistPage(client.getBrowse(browseId), browseId)
                }.getOrNull()
                    ?: runCatching {
                        mapper.mapArtistPage(client.getBrowseAuthenticated(browseId), browseId)
                    }.getOrNull()

                val completed = browsed?.let { completeArtistPage(it) }
                _page.value = completed
                _isLoading.value = false
                if (completed != null) refreshArtwork(completed)
            } catch (e: Exception) {
                e.printStackTrace()
                _isLoading.value = false
            }
        }
    }

    private suspend fun refreshArtwork(artistPage: ArtistPage) {
        if (artistPage.topTracks.isEmpty()) return
        _isRefreshingArtwork.value = true
        try {
            val enrichedTracks = artworkEnricher.enrichArtwork(artistPage.topTracks, limit = 18)
            val current = _page.value ?: return
            if (current.id != artistPage.id) return
            _page.value = current.copy(topTracks = enrichedTracks)
        } finally {
            _isRefreshingArtwork.value = false
        }
    }

    private suspend fun completeArtistPage(page: ArtistPage): ArtistPage = coroutineScope {
        val name = page.name.takeIf { it != "Artiste" && it.isNotBlank() }

        // If name wasn't found from browse, try to resolve it via an artist search
        val resolvedName = name ?: run {
            val searchResult = runCatching {
                mapper.mapSearchResults(client.search(page.id, params = ARTISTS_PARAMS))
                    .firstOrNull { it.type == ItemType.ARTIST }
            }.getOrNull()
            searchResult?.title?.takeIf { it.isNotBlank() }
        }

        val effectiveName = resolvedName ?: page.name

        // If thumbnails are empty, try to get artist thumbnail from search
        val thumbnailsTask = async {
            if (page.thumbnails.isNotEmpty()) page.thumbnails else runCatching {
                mapper.mapSearchResults(client.search(effectiveName, params = ARTISTS_PARAMS))
                    .firstOrNull { it.type == ItemType.ARTIST && it.thumbnails.isNotEmpty() }
                    ?.thumbnails
            }.getOrNull() ?: emptyList()
        }

        val tracksTask = async {
            if (page.topTracks.isNotEmpty()) page.topTracks else runCatching {
                mapper.mapSearchResults(client.search("$effectiveName meilleurs titres", params = SONGS_PARAMS))
                    .filter { it.type == ItemType.SONG }
                    .distinctBy { it.id }
                    .take(12)
            }.getOrDefault(emptyList())
        }
        val albumsTask = async {
            if (page.albums.isNotEmpty()) page.albums else runCatching {
                mapper.mapSearchResults(client.search("$effectiveName albums", params = ALBUMS_PARAMS))
                    .filter { it.type == ItemType.ALBUM }
                    .distinctBy { it.browseId ?: it.id }
                    .take(12)
            }.getOrDefault(emptyList())
        }

        page.copy(
            name = effectiveName,
            thumbnails = thumbnailsTask.await(),
            topTracks = tracksTask.await(),
            albums = albumsTask.await()
        )
    }

    private companion object {
        const val SONGS_PARAMS = "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
        const val ALBUMS_PARAMS = "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"
        const val ARTISTS_PARAMS = "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
    }
}

@Composable
fun AlbumScreen(
    browseId: String,
    onBack: () -> Unit,
    onSongClick: (SongItem, List<SongItem>) -> Unit,
    onRadio: (SongItem) -> Unit,
    viewModel: AlbumDetailViewModel = viewModel()
) {
    val album by viewModel.album.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isRefreshingArtwork by viewModel.isRefreshingArtwork.collectAsState()

    LaunchedEffect(browseId) {
        viewModel.loadAlbum(browseId)
    }

    MediaDetailScaffold(
        title = album?.title ?: "Album",
        isLoading = isLoading,
        onBack = onBack
    ) {
        val details = album
        if (details == null) {
            item { EmptyDetailText("Impossible de charger l’album.") }
        } else {
            item {
                DetailHeader(
                    thumbnails = details.thumbnails,
                    title = details.title,
                    subtitle = details.author.orEmpty(),
                    onPlay = { details.tracks.firstOrNull()?.let { onSongClick(it, details.tracks) } },
                    onShuffle = { details.tracks.randomOrNull()?.let { onSongClick(it, details.tracks) } }
                )
            }
            items(details.tracks, key = { it.id }) { track ->
                PlaylistTrackItem(
                    track = track,
                    animateArtworkUpdates = isRefreshingArtwork,
                    onClick = { onSongClick(track, details.tracks) },
                    onRadio = { onRadio(track) }
                )
            }
        }
    }
}

@Composable
fun ArtistScreen(
    browseId: String,
    onBack: () -> Unit,
    onSongClick: (SongItem, List<SongItem>) -> Unit,
    onRadio: (SongItem) -> Unit,
    onNavigate: (SongItem) -> Unit,
    viewModel: ArtistDetailViewModel = viewModel()
) {
    val page by viewModel.page.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isRefreshingArtwork by viewModel.isRefreshingArtwork.collectAsState()

    LaunchedEffect(browseId) {
        viewModel.loadArtist(browseId)
    }

    MediaDetailScaffold(
        title = page?.name ?: "Artiste",
        isLoading = isLoading,
        onBack = onBack
    ) {
        val artistPage = page
        if (artistPage == null) {
            item { EmptyDetailText("Impossible de charger l'artiste.") }
        } else {
            item {
                DetailHeader(
                    thumbnails = artistPage.thumbnails,
                    title = artistPage.name,
                    subtitle = "Artiste",
                    onPlay = { artistPage.topTracks.firstOrNull()?.let { onSongClick(it, artistPage.topTracks) } },
                    onShuffle = { artistPage.topTracks.randomOrNull()?.let { onSongClick(it, artistPage.topTracks) } }
                )
            }
            if (artistPage.topTracks.isNotEmpty()) {
                item {
                    SectionTitle(
                        title = "Titres populaires",
                        modifier = Modifier.padding(horizontal = 16.dp)
                    )
                }
                items(artistPage.topTracks, key = { it.id }) { track ->
                    PlaylistTrackItem(
                        track = track,
                        animateArtworkUpdates = isRefreshingArtwork,
                        onClick = { onSongClick(track, artistPage.topTracks) },
                        onRadio = { onRadio(track) }
                    )
                }
            }
            if (artistPage.albums.isNotEmpty()) {
                item {
                    HorizontalResultSection(
                        title = "Albums",
                        items = artistPage.albums,
                        onNavigate = onNavigate
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MediaDetailScaffold(
    title: String,
    isLoading: Boolean,
    onBack: () -> Unit,
    content: androidx.compose.foundation.lazy.LazyListScope.() -> Unit
) {
    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Top),
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = "Retour")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)
            )
        }
    ) { padding ->
        if (isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                content()
                item { Spacer(Modifier.height(18.dp)) }
            }
        }
    }
}

@Composable
private fun DetailHeader(
    thumbnails: List<Thumbnail>,
    title: String,
    subtitle: String,
    onPlay: () -> Unit,
    onShuffle: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 18.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        val context = LocalContext.current
        val imageUrl = thumbnails.bestThumbnailUrl()
        AsyncImage(
            model = ImageRequest.Builder(context)
                .data(imageUrl)
                .crossfade(true)
                .build(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(210.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant)
        )
        Spacer(Modifier.height(18.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )
        if (subtitle.isNotBlank()) {
            Text(
                text = subtitle,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }
        Spacer(Modifier.height(16.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Button(
                onClick = onPlay,
                modifier = Modifier.weight(1f),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Lecture")
            }

            Button(
                onClick = onShuffle,
                modifier = Modifier.weight(1f),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = MaterialTheme.colorScheme.primary
                )
            ) {
                Icon(Icons.Filled.Shuffle, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Aléatoire")
            }
        }
    }
}

@Composable
private fun EmptyDetailText(text: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(220.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun List<ArtistInfo>.filterUsefulAlbumArtists(albumTitle: String): List<ArtistInfo> {
    val albumKey = albumTitle.normalizedMusicGlassKey()
    return filter { artist ->
        val nameKey = artist.name.normalizedMusicGlassKey()
        nameKey.isNotBlank() &&
            nameKey != albumKey &&
            !artist.name.isGenericAlbumArtistLabel()
    }
}

private fun String?.withAlbumArtistLine(artists: List<ArtistInfo>): String? {
    if (artists.isEmpty()) return this
    val artistLine = artists.joinToString(", ") { it.name }
    val year = this
        .orEmpty()
        .split("•", "·")
        .map { it.trim() }
        .firstOrNull { it.matches(Regex("\\d{4}")) }
    return listOfNotNull(artistLine, year).joinToString(" • ")
}

private fun String.isGenericAlbumArtistLabel(): Boolean {
    return normalizedMusicGlassKey() in setOf(
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

private fun String.normalizedMusicGlassKey(): String {
    return java.text.Normalizer.normalize(this, java.text.Normalizer.Form.NFD)
        .replace(Regex("\\p{Mn}+"), "")
        .lowercase()
        .trim()
}
