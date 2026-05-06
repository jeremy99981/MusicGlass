package com.musicglass.app.youtubemusic

import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

class ArtworkEnricher(
    private val client: InnerTubeClient,
    private val mapper: InnerTubeJSONMapper
) {
    companion object {
        private const val SONGS_FILTER = "EgWKAQIIAWoMEAMQBBAJEA4QChAF"
        private val artworkCache = ConcurrentHashMap<String, SongItem>()
    }

    suspend fun enrichArtwork(
        tracks: List<SongItem>,
        fallbackAlbum: AlbumInfo? = null,
        limit: Int = 80
    ): List<SongItem> {
        if (tracks.isEmpty()) return tracks

        val result = tracks.toMutableList()
        val cappedCount = minOf(limit, tracks.size)
        val semaphore = Semaphore(6)

        coroutineScope {
            (0 until cappedCount)
                .map { index ->
                    async(Dispatchers.IO) {
                        semaphore.withPermit {
                            index to enrichTrack(tracks[index], fallbackAlbum)
                        }
                    }
                }
                .awaitAll()
                .forEach { (index, enrichedTrack) ->
                    result[index] = enrichedTrack
                }
        }

        return result
    }

    private suspend fun enrichTrack(track: SongItem, fallbackAlbum: AlbumInfo?): SongItem {
        var enriched = track
        if (enriched.album == null && fallbackAlbum != null) {
            enriched = enriched.copy(album = fallbackAlbum)
        }

        val cacheKey = track.artworkCacheKey()
        artworkCache[cacheKey]?.let { cached ->
            return enriched.mergeArtwork(cached, fallbackAlbum)
        }

        val match = bestArtworkMatch(track) ?: return enriched
        if (match.thumbnails.isEmpty()) return enriched

        artworkCache[cacheKey] = match
        return enriched.mergeArtwork(match, fallbackAlbum)
    }

    private suspend fun bestArtworkMatch(track: SongItem): SongItem? {
        val artist = track.primaryArtistName()
        val query = listOf(track.title.trim(), artist.trim())
            .filter { it.isNotEmpty() }
            .joinToString(" ")
            .trim()
        if (query.isEmpty()) return null

        val searchJson = try {
            client.search(query, params = SONGS_FILTER)
        } catch (_: Exception) {
            return null
        }

        val candidates = mapper.mapSearchResults(searchJson)
            .filter { it.type == ItemType.SONG }
            .filter { it.thumbnails.isNotEmpty() }

        return candidates.firstOrNull { it.isStrongArtworkMatch(track) }
            ?: candidates.firstOrNull { it.sharesArtistWith(track) }
            ?: candidates.firstOrNull { it.titleStem() == track.titleStem() }
    }
}

private fun SongItem.mergeArtwork(match: SongItem, fallbackAlbum: AlbumInfo?): SongItem {
    var merged = this

    if (match.thumbnails.isNotEmpty()) {
        merged = merged.copy(thumbnails = match.thumbnails)
    }

    if (merged.artists.isEmpty() && match.artists.isNotEmpty()) {
        merged = merged.copy(artists = match.artists)
    }

    val mergedAlbum = when {
        merged.album == null -> {
            match.album ?: fallbackAlbum?.copy(
                thumbnails = if (match.thumbnails.isNotEmpty()) match.thumbnails else fallbackAlbum.thumbnails
            )
        }
        merged.album.thumbnails.isEmpty() -> merged.album.copy(
            thumbnails = match.album?.thumbnails?.ifEmpty { match.thumbnails } ?: match.thumbnails
        )
        else -> merged.album
    }

    return merged.copy(album = mergedAlbum)
}

private fun SongItem.isStrongArtworkMatch(other: SongItem): Boolean {
    return titleStem() == other.titleStem() && sharesArtistWith(other)
}

private fun SongItem.sharesArtistWith(other: SongItem): Boolean {
    val lhs = artistTokens()
    val rhs = other.artistTokens()
    if (lhs.isEmpty() || rhs.isEmpty()) return false
    return lhs.any { it in rhs } || rhs.any { it in lhs }
}

private fun SongItem.artworkCacheKey(): String {
    return "${titleStem()}|${artistTokens().joinToString(",")}"
}

private fun SongItem.titleStem(): String {
    return title.lowercase()
        .replace(Regex("\\s*[\\(\\[].*?[\\)\\]]"), "")
        .replace(Regex("[^a-z0-9]+"), " ")
        .trim()
}

private fun SongItem.artistTokens(): List<String> {
    val seed = artists.joinToString(",") { it.name }
        .ifBlank { primaryArtistName() }
        .lowercase()
        .replace(" feat. ", ",")
        .replace(" ft. ", ",")
        .replace(" avec ", ",")
        .replace("&", ",")
        .replace("•", ",")

    return seed.split(",", "/", ";", "|")
        .map { it.trim() }
        .filter { it.isNotEmpty() && it != "various artists" && it != "unknown artist" }
}

private fun SongItem.primaryArtistName(): String {
    val direct = artists.firstOrNull()?.name?.trim().orEmpty()
    if (direct.isNotEmpty()) {
        return direct.substringBefore("•").substringBefore(",").trim()
    }
    return title
}
