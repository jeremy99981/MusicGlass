package com.musicglass.app.ui.features

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.musicglass.app.youtubemusic.AuthService
import com.musicglass.app.youtubemusic.InnerTubeClient
import com.musicglass.app.youtubemusic.InnerTubeJSONMapper
import com.musicglass.app.youtubemusic.SongItem
import com.musicglass.app.youtubemusic.bestThumbnailUrl
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

data class LibraryUiState(
    val isAuthenticated: Boolean = false,
    val isLoading: Boolean = false,
    val likedSongs: List<SongItem> = emptyList(),
    val playlists: List<SongItem> = emptyList(),
    val history: List<SongItem> = emptyList(),
    val error: String? = null
)

class LibraryViewModel : ViewModel() {
    private val client = InnerTubeClient()
    private val mapper = InnerTubeJSONMapper()

    private val _state = MutableStateFlow(LibraryUiState(isAuthenticated = AuthService.state.value.isAuthenticated))
    val state: StateFlow<LibraryUiState> = _state

    init {
        viewModelScope.launch {
            AuthService.state.collect { auth ->
                _state.value = _state.value.copy(isAuthenticated = auth.isAuthenticated)
                if (auth.isAuthenticated) load()
            }
        }
    }

    fun load() {
        viewModelScope.launch {
            if (!AuthService.state.value.isAuthenticated) {
                _state.value = LibraryUiState(isAuthenticated = false)
                return@launch
            }

            _state.value = _state.value.copy(isLoading = true, error = null)
            var authFailures = 0

            val likedResult = runCatching { mapper.mapLikedSongs(client.getLikedSongs()) }
            if (likedResult.exceptionOrNull()?.isUnauthorizedResponse() == true) authFailures += 1

            val playlistResult = runCatching { mapper.mapUserPlaylists(client.getUserPlaylists()) }
            if (playlistResult.exceptionOrNull()?.isUnauthorizedResponse() == true) authFailures += 1

            val historyResult = runCatching { mapper.mapYTHistory(client.getYTHistory()) }
            if (historyResult.exceptionOrNull()?.isUnauthorizedResponse() == true) authFailures += 1

            if (authFailures >= 3) {
                AuthService.clear()
                _state.value = LibraryUiState(isAuthenticated = false, error = "Session YouTube Music expirée.")
                return@launch
            }

            val liked = likedResult.getOrDefault(emptyList()).distinctBy { it.id }
            val playlists = playlistResult.getOrDefault(emptyList()).distinctBy { it.id }
            val history = historyResult.getOrDefault(emptyList()).distinctBy { it.id }
            val allFailed = listOf(likedResult, playlistResult, historyResult).all { it.isFailure }

            _state.value = _state.value.copy(
                isAuthenticated = true,
                isLoading = false,
                likedSongs = liked,
                playlists = playlists,
                history = history,
                error = if (allFailed) "Bibliothèque YouTube Music indisponible pour le moment." else null
            )
        }
    }

    fun logout() {
        AuthService.clear()
        _state.value = LibraryUiState(isAuthenticated = false)
    }
}

private fun Throwable.isUnauthorizedResponse(): Boolean {
    val text = message.orEmpty()
    return text.contains("code=401") || text.contains("code=403")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(
    viewModel: LibraryViewModel = viewModel(),
    onLogin: () -> Unit,
    onSongClick: (SongItem, List<SongItem>) -> Unit,
    onRadio: (SongItem) -> Unit,
    onNavigate: (SongItem) -> Unit
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(Unit) {
        viewModel.load()
    }

    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Top),
        topBar = {
            TopAppBar(
                title = { Text("Bibliothèque") },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            if (!state.isAuthenticated) {
                item { LoginInvite(onLogin = onLogin) }
            } else {
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                        LibraryTile(Icons.Filled.MusicNote, "Favoris", "${state.likedSongs.size} morceaux", Modifier.weight(1f))
                        LibraryTile(Icons.Filled.History, "Historique", "${state.history.size} écoutes", Modifier.weight(1f))
                    }
                }

                if (state.isLoading) {
                    item {
                        Box(Modifier.fillMaxWidth().height(96.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator()
                        }
                    }
                }

                state.error?.let { error ->
                    item { Text(error, color = MaterialTheme.colorScheme.error) }
                }

                if (state.playlists.isNotEmpty()) {
                    item { SectionTitle("Mes playlists YouTube Music") }
                    items(state.playlists, key = { "playlist-${it.id}" }) { playlist ->
                        LibraryMediaRow(item = playlist, onClick = { onNavigate(playlist) })
                    }
                }

                if (state.likedSongs.isNotEmpty()) {
                    item { SectionTitle("Favoris") }
                    items(state.likedSongs.take(30), key = { "liked-${it.id}" }) { song ->
                        SearchListItem(
                            song,
                            onClick = { onSongClick(song, state.likedSongs) },
                            onRadio = { onRadio(song) }
                        )
                    }
                }

                if (state.history.isNotEmpty()) {
                    item { SectionTitle("Écoutés récemment") }
                    items(state.history.take(30), key = { "history-${it.id}" }) { song ->
                        SearchListItem(
                            song,
                            onClick = { onSongClick(song, state.history) },
                            onRadio = { onRadio(song) }
                        )
                    }
                }

                if (!state.isLoading &&
                    state.error == null &&
                    state.playlists.isEmpty() &&
                    state.likedSongs.isEmpty() &&
                    state.history.isEmpty()
                ) {
                    item {
                        Text(
                            "Votre bibliothèque YouTube Music est vide ou n'a pas encore été synchronisée.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LoginInvite(onLogin: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 60.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(Icons.Filled.AccountCircle, contentDescription = null, modifier = Modifier.size(56.dp))
        Spacer(Modifier.height(14.dp))
        Text("Connectez YouTube Music", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(
            "Vos playlists, favoris et écoutes récentes apparaîtront ici.",
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(18.dp))
        Button(onClick = onLogin) {
            Text("Se connecter")
        }
    }
}

@Composable
private fun LibraryTile(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .clickable { }
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(34.dp))
        Spacer(Modifier.width(10.dp))
        Column {
            Text(title, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }
    }
}

@Composable
private fun LibraryMediaRow(item: SongItem, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        AsyncImage(
            model = item.thumbnails.bestThumbnailUrl(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(8.dp))
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(item.title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                item.artists.joinToString(", ") { it.name }.ifBlank { "Playlist" },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}
