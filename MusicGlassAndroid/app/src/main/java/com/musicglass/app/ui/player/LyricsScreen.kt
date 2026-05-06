package com.musicglass.app.ui.player

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.musicglass.app.youtubemusic.Lyrics
import com.musicglass.app.youtubemusic.LyricsService
import kotlinx.coroutines.launch

@Composable
fun LyricsScreen(
    title: String,
    artistLine: String,
    artworkUrl: String?,
    durationSeconds: Double?,
    onDismiss: () -> Unit
) {
    var lyrics by remember(title) { mutableStateOf<Lyrics?>(null) }
    var isLoading by remember(title) { mutableStateOf(false) }
    var errorMessage by remember(title) { mutableStateOf<String?>(null) }
    
    val coroutineScope = rememberCoroutineScope()
    val lyricsService = remember { LyricsService() }

    LaunchedEffect(title) {
        isLoading = true
        errorMessage = null
        try {
            val fetchedLyrics = lyricsService.getLyrics(
                title = title,
                artistName = artistLine.takeIf { it.isNotBlank() },
                albumName = null,
                durationSeconds = durationSeconds
            )
            if (fetchedLyrics != null) {
                lyrics = fetchedLyrics
            } else {
                errorMessage = "Paroles indisponibles"
            }
        } catch (e: Exception) {
            errorMessage = e.message ?: "Erreur inconnue"
        } finally {
            isLoading = false
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .padding(bottom = 24.dp)
    ) {
        Text(
            text = "Paroles",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
            textAlign = TextAlign.Center
        )

        Row(
            modifier = Modifier.fillMaxWidth().padding(bottom = 24.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(artworkUrl)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(68.dp)
                    .clip(RoundedCornerShape(8.dp))
            )
            Spacer(modifier = Modifier.width(16.dp))
            Column {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onBackground
                )
                Text(
                    text = artistLine,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        if (isLoading) {
            Box(modifier = Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else if (errorMessage != null) {
            Box(modifier = Modifier.fillMaxWidth().height(200.dp), contentAlignment = Alignment.Center) {
                Text(errorMessage!!, color = MaterialTheme.colorScheme.error)
            }
        } else if (lyrics != null) {
            LazyColumn(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                if (lyrics!!.syncedLines.isEmpty()) {
                    item {
                        Text(
                            text = lyrics!!.plainText,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onBackground,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                } else {
                    items(lyrics!!.syncedLines) { line ->
                        Text(
                            text = line.text,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onBackground,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }
        }
    }
}
