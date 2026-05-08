package com.musicglass.app.ui.features

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import com.musicglass.app.persistence.LibraryRepository

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
        // Immediate restoration from repository cache if available
        LibraryRepository.getCachedData()?.let { cached ->
            _state.value = _state.value.copy(
                likedSongs = cached.likedSongs,
                playlists = cached.playlists,
                history = cached.history
            )
        }

        viewModelScope.launch {
            AuthService.state.collect { auth ->
                _state.value = _state.value.copy(isAuthenticated = auth.isAuthenticated)
                if (auth.isAuthenticated) load(force = false)
            }
        }
    }

    fun load(force: Boolean = false) {
        viewModelScope.launch {
            if (!AuthService.state.value.isAuthenticated) {
                _state.value = LibraryUiState(isAuthenticated = false)
                LibraryRepository.clearCache()
                return@launch
            }

            // Memory Cache: Skip if data already exists and not forcing refresh
            // Also check repository cache if state is empty but repository is not
            val hasData = _state.value.playlists.isNotEmpty() || LibraryRepository.hasCache()
            if (!force && hasData && _state.value.playlists.isNotEmpty()) {
                return@launch
            }
            
            // If we have repository cache but state is empty, restore it first before fetching
            if (_state.value.playlists.isEmpty()) {
                LibraryRepository.getCachedData()?.let { cached ->
                    _state.value = _state.value.copy(
                        likedSongs = cached.likedSongs,
                        playlists = cached.playlists,
                        history = cached.history
                    )
                }
            }

            // Only show loader if we don't have data yet
            _state.value = _state.value.copy(
                isLoading = _state.value.playlists.isEmpty(),
                error = null
            )
            
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
                likedSongs = if (likedResult.isSuccess) liked else _state.value.likedSongs,
                playlists = if (playlistResult.isSuccess) playlists else _state.value.playlists,
                history = if (historyResult.isSuccess) history else _state.value.history,
                error = if (allFailed) "Bibliothèque YouTube Music indisponible pour le moment." else null
            )

            // Update Repository Cache
            if (!allFailed) {
                LibraryRepository.updateCache(
                    likedSongs = _state.value.likedSongs,
                    playlists = _state.value.playlists,
                    history = _state.value.history
                )
            }
        }
    }

    fun logout() {
        AuthService.clear()
        LibraryRepository.clearCache()
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
    onNavigate: (SongItem) -> Unit,
    onArtistsClick: () -> Unit
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(Unit) {
        viewModel.load(force = false)
    }

    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Top),
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(bottom = 100.dp), // Extra padding for mini-player
            verticalArrangement = Arrangement.spacedBy(28.dp)
        ) {
            // Header
            item {
                LibraryHeader()
            }

            if (!state.isAuthenticated) {
                item { LoginInvite(onLogin = onLogin) }
            } else {
                // Stats Grid
                item {
                    LibraryStatsGrid(
                        likedCount = state.likedSongs.size,
                        playlistsCount = state.playlists.size
                    )
                }

                // Shortcuts Grid
                item {
                    LibraryShortcutGrid(onArtistsClick = onArtistsClick)
                }

                // Only show loader if we have NO data. Otherwise, load in background silently.
                if (state.isLoading && state.playlists.isEmpty()) {
                    item {
                        Box(Modifier.fillMaxWidth().height(120.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(strokeWidth = 3.dp)
                        }
                    }
                }

                state.error?.let { error ->
                    item { 
                        Text(
                            text = error, 
                            color = MaterialTheme.colorScheme.error,
                            modifier = Modifier.padding(horizontal = 24.dp),
                            style = MaterialTheme.typography.bodyMedium
                        ) 
                    }
                }

                // Playlists Section
                if (state.playlists.isNotEmpty()) {
                    item {
                        LibraryPlaylistsSection(
                            playlists = state.playlists,
                            onPlaylistClick = onNavigate
                        )
                    }
                }

                // Recently Played Section
                if (state.history.isNotEmpty()) {
                    item {
                        RecentlyPlayedSection(
                            history = state.history,
                            onSongClick = onSongClick,
                            onRadio = onRadio
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
                        Box(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 20.dp), contentAlignment = Alignment.Center) {
                            Text(
                                "Votre bibliothèque est vide.",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.Center,
                                style = MaterialTheme.typography.bodyLarge
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LibraryHeader() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 16.dp)
    ) {
        Text(
            text = "Bibliothèque",
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.ExtraBold,
            color = MaterialTheme.colorScheme.onBackground,
            letterSpacing = (-0.5).sp
        )
        Text(
            text = "Votre musique, vos playlists, vos favoris.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 4.dp)
        )
    }
}

@Composable
private fun LibraryStatsGrid(likedCount: Int, playlistsCount: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        LibraryStatCard(
            title = "TITRES AIMÉS",
            count = likedCount,
            icon = Icons.Filled.Favorite,
            iconColor = Color(0xFFD84B5F), // More vibrant pink
            modifier = Modifier.weight(1f)
        )
        LibraryStatCard(
            title = "PLAYLISTS",
            count = playlistsCount,
            icon = Icons.Filled.LibraryMusic,
            iconColor = MaterialTheme.colorScheme.primary,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun LibraryStatCard(
    title: String,
    count: Int,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconColor: Color,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.height(118.dp),
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f)
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
    ) {
        Box(modifier = Modifier.fillMaxSize().padding(20.dp)) {
            // Icon Top Start
            Box(
                modifier = Modifier
                    .size(42.dp)
                    .align(Alignment.TopStart)
                    .clip(CircleShape)
                    .background(iconColor.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, contentDescription = null, tint = iconColor, modifier = Modifier.size(22.dp))
            }
            
            // Large Number Right Center -> Moved to TopEnd
            Text(
                text = count.toString(),
                style = MaterialTheme.typography.headlineLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 2.dp) // Optical alignment with icon center
            )

            // Label Bottom Start
            Text(
                text = title,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.ExtraBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                letterSpacing = 0.5.sp,
                modifier = Modifier.align(Alignment.BottomStart)
            )
        }
    }
}

@Composable
private fun LibraryShortcutGrid(onArtistsClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            LibraryShortcutCard(
                title = "Artistes",
                icon = Icons.Filled.Person,
                modifier = Modifier.weight(1f),
                onClick = onArtistsClick
            )
            LibraryShortcutCard(
                title = "Albums",
                icon = Icons.Filled.Album,
                modifier = Modifier.weight(1f),
                onClick = {}
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            LibraryShortcutCard(
                title = "Téléchargements",
                icon = Icons.Filled.CloudDownload,
                modifier = Modifier.weight(1f),
                onClick = {}
            )
            LibraryShortcutCard(
                title = "Historique",
                icon = Icons.Filled.History,
                modifier = Modifier.weight(1f),
                onClick = {}
            )
        }
    }
}

@Composable
private fun LibraryShortcutCard(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Surface(
        modifier = modifier
            .height(82.dp) // Increased height to prevent text issues
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(24.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Icon(
                icon, 
                contentDescription = null, 
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp)
            )
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                lineHeight = 20.sp
            )
        }
    }
}

@Composable
private fun LibraryPlaylistsSection(
    playlists: List<SongItem>,
    onPlaylistClick: (SongItem) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Mes playlists",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
            Surface(
                color = MaterialTheme.colorScheme.surfaceVariant,
                shape = CircleShape,
                modifier = Modifier.size(32.dp)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        playlists.size.toString(),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
        
        LazyRow(
            contentPadding = PaddingValues(horizontal = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            items(playlists, key = { it.id }) { playlist ->
                LibraryPlaylistCard(playlist, onClick = { onPlaylistClick(playlist) })
            }
        }
    }
}

@Composable
private fun LibraryPlaylistCard(playlist: SongItem, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .width(156.dp)
            .clickable(onClick = onClick)
    ) {
        Box(
            modifier = Modifier
                .size(156.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
        ) {
            AsyncImage(
                model = playlist.thumbnails.bestThumbnailUrl(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
            // YT Music Badge
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(10.dp),
                color = Color.Black.copy(alpha = 0.65f),
                shape = CircleShape
            ) {
                Text(
                    text = "YT Music",
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                    color = Color.White,
                    style = MaterialTheme.typography.labelSmall,
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Bold
                )
            }
        }
        Spacer(Modifier.height(10.dp))
        Text(
            text = playlist.title,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            color = MaterialTheme.colorScheme.onSurface
        )
        Text(
            text = playlist.artists.joinToString(", ") { it.name }.ifBlank { "Playlist" },
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun RecentlyPlayedSection(
    history: List<SongItem>,
    onSongClick: (SongItem, List<SongItem>) -> Unit,
    onRadio: (SongItem) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text(
            text = "Écoutés récemment",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 24.dp)
        )
        
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            history.take(6).forEach { song ->
                SearchListItem(
                    item = song,
                    onClick = { onSongClick(song, history) },
                    onRadio = { onRadio(song) }
                )
            }
        }
    }
}

@Composable
private fun LoginInvite(onLogin: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Surface(
            modifier = Modifier.size(80.dp),
            shape = CircleShape,
            color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.4f)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.AccountCircle, contentDescription = null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.primary)
            }
        }
        Spacer(Modifier.height(24.dp))
        Text("Connectez YouTube Music", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(
            "Vos playlists, favoris et écoutes récentes apparaîtront ici.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            style = MaterialTheme.typography.bodyLarge
        )
        Spacer(Modifier.height(32.dp))
        Button(
            onClick = onLogin,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(20.dp),
            contentPadding = PaddingValues(16.dp)
        ) {
            Text("Se connecter", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        }
    }
}
