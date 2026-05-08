package com.musicglass.app.ui.features.library.artists

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
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
import com.musicglass.app.persistence.PlaybackHistoryRepository
import com.musicglass.app.youtubemusic.InnerTubeClient
import com.musicglass.app.youtubemusic.InnerTubeJSONMapper
import com.musicglass.app.youtubemusic.SongItem
import com.musicglass.app.youtubemusic.bestThumbnailUrl
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

data class ArtistUiModel(
    val name: String,
    val browseId: String?,
    val artworkUrl: String?,
    val listenCount: Int,
    val trackCount: Int
)

data class ArtistsUiState(
    val isLoading: Boolean = false,
    val artists: List<ArtistUiModel> = emptyList(),
    val topArtists: List<ArtistUiModel> = emptyList(),
    val otherArtists: List<ArtistUiModel> = emptyList(),
    val searchQuery: String = "",
    val totalCount: Int = 0
)

class ArtistsViewModel : ViewModel() {
    private val client = InnerTubeClient()
    private val mapper = InnerTubeJSONMapper()
    
    private val _state = MutableStateFlow(ArtistsUiState())
    val state: StateFlow<ArtistsUiState> = _state

    init {
        loadArtists()
    }

    fun loadArtists() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true)
            
            // 1. Get history from local repository
            val localHistory = PlaybackHistoryRepository.history.value
            
            val artistMap = mutableMapOf<String, ArtistStats>()
            
            localHistory.forEach { song ->
                song.artists.forEach { artistInfo ->
                    val stats = artistMap.getOrPut(artistInfo.name) { 
                        ArtistStats(
                            name = artistInfo.name, 
                            browseId = artistInfo.browseId, 
                            artworkUrl = song.thumbnails.bestThumbnailUrl() 
                        ) 
                    }
                    stats.listenCount++
                    // Increment track count if we haven't seen this song for this artist yet
                    if (song.id !in stats.songIds) {
                        stats.songIds.add(song.id)
                        stats.trackCount++
                    }
                }
            }

            val allArtists = artistMap.values
                .map { 
                    ArtistUiModel(
                        name = it.name,
                        browseId = it.browseId,
                        artworkUrl = it.artworkUrl,
                        listenCount = it.listenCount,
                        trackCount = it.trackCount
                    )
                }
                .sortedByDescending { it.listenCount }

            updateList(allArtists)
        }
    }

    private fun updateList(allArtists: List<ArtistUiModel>) {
        val query = _state.value.searchQuery.lowercase()
        val filtered = if (query.isBlank()) {
            allArtists
        } else {
            allArtists.filter { it.name.lowercase().contains(query) }
        }

        val top = if (query.isBlank()) filtered.take(3) else emptyList()
        val other = if (query.isBlank()) filtered.drop(3) else filtered

        _state.value = _state.value.copy(
            isLoading = false,
            artists = allArtists,
            topArtists = top,
            otherArtists = other,
            totalCount = allArtists.size
        )
    }

    fun onSearch(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        updateList(_state.value.artists)
    }

    private class ArtistStats(
        val name: String,
        val browseId: String?,
        val artworkUrl: String?,
        var listenCount: Int = 0,
        var trackCount: Int = 0,
        val songIds: MutableSet<String> = mutableSetOf()
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArtistsScreen(
    onBack: () -> Unit,
    onArtistClick: (String, String?) -> Unit,
    viewModel: ArtistsViewModel = viewModel()
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        contentWindowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Top)
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(bottom = 100.dp)
        ) {
            // Top Bar
            item {
                ArtistsHeader(
                    count = state.totalCount,
                    onBack = onBack
                )
            }

            // Search Bar
            item {
                ArtistSearchBar(
                    query = state.searchQuery,
                    onQueryChange = { viewModel.onSearch(it) }
                )
            }

            if (state.isLoading && state.artists.isEmpty()) {
                item {
                    Box(Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
            } else if (state.artists.isEmpty()) {
                item {
                    EmptyArtistsState()
                }
            } else {
                // Top Artists Podium
                if (state.topArtists.isNotEmpty()) {
                    item {
                        SectionTitle("Top artistes")
                        TopArtistsCard(
                            artists = state.topArtists,
                            onArtistClick = onArtistClick
                        )
                    }
                }

                // Other Artists
                if (state.otherArtists.isNotEmpty()) {
                    item {
                        SectionTitle(if (state.searchQuery.isBlank()) "Autres artistes" else "Résultats")
                    }
                    items(state.otherArtists) { artist ->
                        ArtistListItem(
                            artist = artist,
                            onClick = { onArtistClick(artist.name, artist.browseId) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ArtistsHeader(count: Int, onBack: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        FilledTonalIconButton(
            onClick = onBack,
            modifier = Modifier.size(44.dp),
            shape = CircleShape
        ) {
            Icon(Icons.Filled.ArrowBack, contentDescription = "Retour")
        }
        
        Text(
            text = "Artistes",
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.ExtraBold,
            modifier = Modifier.weight(1f)
        )

        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(12.dp)
        ) {
            Text(
                text = count.toString(),
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ArtistSearchBar(query: String, onQueryChange: (String) -> Unit) {
    TextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 12.dp)
            .height(56.dp),
        placeholder = { Text("Rechercher un artiste") },
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
        shape = RoundedCornerShape(16.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
            disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
        ),
        singleLine = true
    )
}

@Composable
private fun SectionTitle(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleLarge,
        fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp)
    )
}

@Composable
private fun TopArtistsCard(
    artists: List<ArtistUiModel>,
    onArtistClick: (String, String?) -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp),
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 24.dp, horizontal = 12.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.Bottom
        ) {
            // Rank 2 (Left)
            if (artists.size >= 2) {
                TopArtistPodiumItem(
                    artist = artists[1],
                    rank = 2,
                    avatarSize = 72.dp,
                    onClick = { onArtistClick(artists[1].name, artists[1].browseId) }
                )
            }

            // Rank 1 (Center)
            if (artists.isNotEmpty()) {
                TopArtistPodiumItem(
                    artist = artists[0],
                    rank = 1,
                    avatarSize = 96.dp,
                    isMain = true,
                    onClick = { onArtistClick(artists[0].name, artists[0].browseId) }
                )
            }

            // Rank 3 (Right)
            if (artists.size >= 3) {
                TopArtistPodiumItem(
                    artist = artists[2],
                    rank = 3,
                    avatarSize = 72.dp,
                    onClick = { onArtistClick(artists[2].name, artists[2].browseId) }
                )
            }
        }
    }
}

@Composable
private fun TopArtistPodiumItem(
    artist: ArtistUiModel,
    rank: Int,
    avatarSize: androidx.compose.ui.unit.Dp,
    isMain: Boolean = false,
    onClick: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .width(avatarSize + 20.dp)
            .clickable(onClick = onClick)
    ) {
        Box(contentAlignment = Alignment.BottomEnd) {
            AsyncImage(
                model = artist.artworkUrl,
                contentDescription = artist.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(avatarSize)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant)
            )
            
            val badgeColor = when (rank) {
                1 -> MaterialTheme.colorScheme.primary
                2 -> MaterialTheme.colorScheme.secondary
                else -> MaterialTheme.colorScheme.tertiary
            }
            
            Surface(
                color = badgeColor,
                shape = CircleShape,
                modifier = Modifier.size(if (isMain) 28.dp else 24.dp)
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        text = rank.toString(),
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                }
            }
        }
        
        Spacer(Modifier.height(12.dp))
        
        Text(
            text = artist.name,
            style = if (isMain) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center
        )
        
        Text(
            text = "${artist.listenCount} écoutes",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun ArtistListItem(artist: ArtistUiModel, onClick: () -> Unit) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 4.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(24.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AsyncImage(
                model = artist.artworkUrl,
                contentDescription = artist.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(56.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant)
            )
            
            Spacer(Modifier.width(16.dp))
            
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = artist.name,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "${artist.trackCount} titre${if (artist.trackCount > 1) "s" else ""}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            
            Icon(
                Icons.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
            )
        }
    }
}

@Composable
private fun EmptyArtistsState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 80.dp, horizontal = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            Icons.Filled.Person,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.4f)
        )
        Spacer(Modifier.height(24.dp))
        Text(
            "Aucun artiste pour le moment",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(8.dp))
        Text(
            "Écoutez quelques titres pour voir vos artistes apparaître ici.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}
