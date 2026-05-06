package com.musicglass.app.ui.features

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.musicglass.app.youtubemusic.HomeSection
import com.musicglass.app.youtubemusic.SongItem
import com.musicglass.app.youtubemusic.bestThumbnailUrl
import java.util.Calendar

@Composable
fun HomeScreen(
    viewModel: HomeViewModel = viewModel(),
    onSongClick: (SongItem) -> Unit = {},
    onRadio: (SongItem) -> Unit = {}
) {
    val homeFeed by viewModel.homeFeed.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()

    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Top)
    ) { paddingValues ->
        if (isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues)
            ) {
                item {
                    HomeHeader()
                }
                items(homeFeed) { section ->
                    HomeSectionView(section = section, onSongClick = onSongClick, onRadio = onRadio)
                }
            }
        }
    }
}

@Composable
private fun HomeHeader() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, top = 18.dp, end = 16.dp, bottom = 18.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = greetingForCurrentTime(),
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.headlineLarge,
            color = MaterialTheme.colorScheme.onBackground
        )
        Text(
            text = "Recommandations, playlists du moment et découvertes pour vous",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

private fun greetingForCurrentTime(): String {
    return when (Calendar.getInstance().get(Calendar.HOUR_OF_DAY)) {
        in 5..11 -> "Bonjour"
        in 12..17 -> "Bon après-midi"
        else -> "Bonsoir"
    }
}

@Composable
fun HomeSectionView(
    section: HomeSection,
    onSongClick: (SongItem) -> Unit = {},
    onRadio: (SongItem) -> Unit = {}
) {
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
        Text(
            text = section.title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            color = MaterialTheme.colorScheme.onBackground
        )
        
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            items(section.items) { item ->
                SongCard(item = item, onSongClick = onSongClick, onRadio = onRadio)
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SongCard(
    item: SongItem,
    onSongClick: (SongItem) -> Unit = {},
    onRadio: (SongItem) -> Unit = {}
) {
    Column(
        modifier = Modifier
            .width(160.dp)
            .combinedClickable(
                onClick = { onSongClick(item) },
                onLongClick = { onRadio(item) }
            )
    ) {
        Card(
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier
                .width(160.dp)
                .height(160.dp),
            elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
        ) {
            val imageUrl = item.thumbnails.bestThumbnailUrl()
            AsyncImage(
                model = imageUrl,
                contentDescription = item.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = item.title,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        if (item.artists.isNotEmpty()) {
            Text(
                text = item.artists.first().name,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}
