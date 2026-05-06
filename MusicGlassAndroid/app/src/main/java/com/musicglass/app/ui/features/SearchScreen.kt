package com.musicglass.app.ui.features

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.musicglass.app.youtubemusic.InnerTubeClient
import com.musicglass.app.youtubemusic.InnerTubeJSONMapper
import com.musicglass.app.youtubemusic.ItemType
import com.musicglass.app.youtubemusic.SongItem
import com.musicglass.app.youtubemusic.bestThumbnailUrl
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

enum class SearchFilter(val title: String, val params: String?) {
    ALL("Tout", null),
    SONGS("Morceaux", "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"),
    ALBUMS("Albums", "EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D"),
    ARTISTS("Artistes", "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"),
    PLAYLISTS("Playlists", "EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D"),
    VIDEOS("Vidéos", "EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D")
}

data class SearchUiState(
    val query: String = "",
    val filter: SearchFilter = SearchFilter.ALL,
    val results: List<SongItem> = emptyList(),
    val suggestions: List<String> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null
)

class SearchViewModel : ViewModel() {
    private val client = InnerTubeClient()
    private val mapper = InnerTubeJSONMapper()
    private var searchJob: Job? = null

    private val _state = MutableStateFlow(SearchUiState())
    val state: StateFlow<SearchUiState> = _state

    fun setQuery(query: String) {
        _state.value = _state.value.copy(query = query)
        scheduleSearch()
    }

    fun setFilter(filter: SearchFilter) {
        _state.value = _state.value.copy(filter = filter)
        scheduleSearch(immediate = true)
    }

    private fun scheduleSearch(immediate: Boolean = false) {
        searchJob?.cancel()
        val query = _state.value.query.trim()
        if (query.isEmpty()) {
            _state.value = _state.value.copy(results = emptyList(), suggestions = emptyList(), isLoading = false, error = null)
            return
        }

        searchJob = viewModelScope.launch {
            if (!immediate) delay(350)
            performSearch(query)
        }
    }

    private suspend fun performSearch(query: String) {
        _state.value = _state.value.copy(isLoading = true, error = null)
        try {
            val filter = _state.value.filter
            val results = if (filter == SearchFilter.ALL) {
                artistFocusedSearch(query)
            } else {
                searchWithFilter(query, filter.params)
            }
            // Fetch suggestions in parallel
            val suggestions = runCatching {
                val suggestionsJson = client.getSearchSuggestions(query)
                mapper.mapSuggestions(suggestionsJson)
            }.getOrDefault(emptyList())
            _state.value = _state.value.copy(results = results, suggestions = suggestions, isLoading = false)
        } catch (e: CancellationException) {
            if (_state.value.query.trim() == query) {
                _state.value = _state.value.copy(isLoading = false)
            }
            throw e
        } catch (e: Exception) {
            _state.value = _state.value.copy(isLoading = false, error = e.message ?: "Recherche impossible")
        }
    }

    private suspend fun searchWithFilter(query: String, params: String?): List<SongItem> {
        val json = client.search(query, params = params)
        return mapper.mapSearchResults(json).distinctBy { it.stableSearchKey() }
    }

    private suspend fun artistFocusedSearch(query: String): List<SongItem> = coroutineScope {
        val allTask = async { searchWithFallback(query, null) }
        val artistsTask = async { searchWithFallback(query, SearchFilter.ARTISTS.params) }
        val songsTask = async { searchWithFallback("$query meilleurs titres", SearchFilter.SONGS.params) }
        val albumsTask = async { searchWithFallback("$query albums", SearchFilter.ALBUMS.params) }

        val all = allTask.await()
        val artists = (artistsTask.await() + all)
            .filter { it.type == ItemType.ARTIST }
            .distinctBy { it.stableSearchKey() }
            .take(6)
        val songs = (songsTask.await() + all)
            .filter { it.type == ItemType.SONG }
            .filter { it.artists.isNotEmpty() }
            .distinctBy { it.id }
            .take(20)
        val albums = (albumsTask.await() + all)
            .filter { it.type == ItemType.ALBUM }
            .distinctBy { it.stableSearchKey() }
            .take(14)
        val playlists = all
            .filter { it.type == ItemType.PLAYLIST }
            .distinctBy { it.stableSearchKey() }
            .take(12)
        val videos = all
            .filter { it.type != ItemType.ARTIST && it.type != ItemType.SONG && it.type != ItemType.ALBUM && it.type != ItemType.PLAYLIST }

        artists + songs + albums + playlists + videos
    }

    private suspend fun searchWithFallback(query: String, params: String?): List<SongItem> {
        return try {
            searchWithFilter(query, params)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun submitSuggestion(suggestion: String) {
        _state.value = _state.value.copy(query = suggestion)
        scheduleSearch(immediate = true)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    viewModel: SearchViewModel = viewModel(),
    onSongClick: (SongItem, List<SongItem>) -> Unit,
    onRadio: (SongItem) -> Unit,
    onNavigate: (SongItem) -> Unit
) {
    val state by viewModel.state.collectAsState()
    val songs = state.results.filter { it.type == ItemType.SONG }
    val albums = state.results.filter { it.type == ItemType.ALBUM }
    val artists = state.results.filter { it.type == ItemType.ARTIST }
    val playlists = state.results.filter { it.type == ItemType.PLAYLIST }

    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Top),
        topBar = {
            TopAppBar(
                title = { Text("Recherche") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            item {
                OutlinedTextField(
                    value = state.query,
                    onValueChange = viewModel::setQuery,
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    label = { Text("Morceaux, albums, artistes") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp)
                )
            }

            item {
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = PaddingValues(horizontal = 16.dp)
                ) {
                    items(SearchFilter.values().toList()) { filter ->
                        FilterChip(
                            selected = state.filter == filter,
                            onClick = { viewModel.setFilter(filter) },
                            label = { Text(filter.title) }
                        )
                    }
                }
            }

            if (state.suggestions.isNotEmpty() && state.query.isNotBlank()) {
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Spacer(Modifier.width(8.dp))
                        state.suggestions.take(8).forEach { suggestion ->
                            Surface(
                                onClick = { viewModel.submitSuggestion(suggestion) },
                                shape = CircleShape,
                                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
                                modifier = Modifier.height(36.dp)
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 14.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    Icon(
                                        Icons.Filled.Search,
                                        contentDescription = null,
                                        modifier = Modifier.size(16.dp),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                    Text(
                                        text = suggestion,
                                        style = MaterialTheme.typography.labelLarge,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                        Spacer(Modifier.width(8.dp))
                    }
                }
            }

            when {
                state.query.isBlank() -> item {
                    EmptySearchState()
                }
                state.isLoading && state.results.isEmpty() -> item {
                    Box(Modifier.fillMaxWidth().height(160.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                state.error != null -> item {
                    Text(state.error ?: "", color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(horizontal = 16.dp))
                }
                state.results.isEmpty() -> item {
                    Text("Aucun résultat. Essayez une autre recherche.", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 16.dp))
                }
                else -> {
                    if (artists.isNotEmpty() && state.filter == SearchFilter.ALL) {
                        item { HorizontalResultSection("Artistes", artists, onNavigate) }
                    }
                    if (songs.isNotEmpty()) {
                        item { SectionTitle(if (artists.isNotEmpty() && state.filter == SearchFilter.ALL) "Meilleurs titres" else "Morceaux", modifier = Modifier.padding(horizontal = 16.dp)) }
                        items(songs, key = { "song-${it.id}" }) { song ->
                            SearchListItem(
                                item = song,
                                onClick = { onSongClick(song, songs) },
                                onRadio = { onRadio(song) }
                            )
                        }
                    }
                    if (albums.isNotEmpty()) {
                        item { HorizontalResultSection("Albums", albums, onNavigate) }
                    }
                    if (artists.isNotEmpty() && state.filter != SearchFilter.ALL) {
                        item { HorizontalResultSection("Artistes", artists, onNavigate) }
                    }
                    if (playlists.isNotEmpty()) {
                        item { HorizontalResultSection("Playlists", playlists, onNavigate) }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptySearchState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 64.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(Icons.Filled.Search, contentDescription = null, modifier = Modifier.size(44.dp))
        Spacer(Modifier.height(12.dp))
        Text("Trouver votre musique", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text("Recherchez morceaux, albums, artistes et playlists.", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun SectionTitle(title: String, modifier: Modifier = Modifier) {
    Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, modifier = modifier)
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SearchListItem(item: SongItem, onClick: () -> Unit, onRadio: (() -> Unit)? = null) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = onClick,
                onLongClick = { onRadio?.invoke() }
            )
            .padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        AsyncImage(
            model = item.thumbnails.bestThumbnailUrl(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(54.dp)
                .clip(RoundedCornerShape(8.dp))
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
            Text(
                item.artists.joinToString(", ") { it.name },
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        item.durationSeconds?.let { duration ->
            Text(
                text = duration.toTrackDurationText(),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(start = 8.dp)
            )
        }
        if (onRadio != null) {
            TrackActionsMenu(
                onPlay = onClick,
                onRadio = onRadio
            )
        }
    }
}

@Composable
fun HorizontalResultSection(title: String, items: List<SongItem>, onNavigate: (SongItem) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionTitle(
            title = title,
            modifier = Modifier.padding(horizontal = 16.dp)
        )
        LazyRow(
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            items(items, key = { "${it.type}-${it.id}" }) { item ->
                Column(
                    modifier = Modifier
                        .width(140.dp)
                        .clickable { onNavigate(item) }
                ) {
                    AsyncImage(
                        model = item.thumbnails.bestThumbnailUrl(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .size(140.dp)
                            .clip(if (item.type == com.musicglass.app.youtubemusic.ItemType.ARTIST) androidx.compose.foundation.shape.CircleShape else RoundedCornerShape(12.dp))
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                    Text(
                        item.artists.joinToString(", ") { it.name },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

private fun SongItem.stableSearchKey(): String {
    return "${type.name}:${browseId ?: id}"
}

private fun Long.toTrackDurationText(): String {
    val minutes = this / 60
    val seconds = this % 60
    return "$minutes:${seconds.toString().padStart(2, '0')}"
}
