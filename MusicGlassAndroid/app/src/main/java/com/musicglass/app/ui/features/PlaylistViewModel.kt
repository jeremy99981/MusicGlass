package com.musicglass.app.ui.features

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.musicglass.app.youtubemusic.AlbumInfo
import com.musicglass.app.youtubemusic.ArtworkEnricher
import com.musicglass.app.youtubemusic.InnerTubeClient
import com.musicglass.app.youtubemusic.InnerTubeJSONMapper
import com.musicglass.app.youtubemusic.PlaylistDetails
import com.musicglass.app.youtubemusic.Thumbnail
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class PlaylistViewModel : ViewModel() {
    private val client = InnerTubeClient()
    private val mapper = InnerTubeJSONMapper()
    private val artworkEnricher = ArtworkEnricher(client, mapper)

    private val _playlistDetails = MutableStateFlow<PlaylistDetails?>(null)
    val playlistDetails: StateFlow<PlaylistDetails?> = _playlistDetails

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading

    private val _isRefreshingArtwork = MutableStateFlow(false)
    val isRefreshingArtwork: StateFlow<Boolean> = _isRefreshingArtwork

    fun loadPlaylist(browseId: String) {
        if (_playlistDetails.value?.id == browseId) return

        viewModelScope.launch {
            _isLoading.value = true
            try {
                val details = loadPlaylistDetails(browseId)
                _playlistDetails.value = details
                _isLoading.value = false
                if (details != null) {
                    refreshArtwork(details)
                }
            } catch (e: Exception) {
                e.printStackTrace()
                _isLoading.value = false
            } finally {
                if (_isLoading.value) {
                    _isLoading.value = false
                }
            }
        }
    }

    private suspend fun loadPlaylistDetails(rawBrowseId: String): PlaylistDetails? {
        val browseCandidates = buildList {
            add(rawBrowseId)
            if (!rawBrowseId.startsWith("VL")) add("VL$rawBrowseId")
        }.distinct()

        for (candidate in browseCandidates) {
            val publicDetails = runCatching {
                mapper.mapPlaylistDetails(client.getBrowse(candidate), candidate)
            }.getOrNull()
            if (publicDetails?.tracks?.isNotEmpty() == true) return publicDetails

            val authenticatedDetails = runCatching {
                mapper.mapPlaylistDetails(client.getBrowseAuthenticated(candidate), candidate)
            }.getOrNull()
            if (authenticatedDetails?.tracks?.isNotEmpty() == true) return authenticatedDetails

            val queueTracks = runCatching {
                mapper.mapNextTracks(client.getPlaylistQueue(candidate.removePrefix("VL")))
            }.getOrDefault(emptyList())
            val authenticatedQueueTracks = if (queueTracks.isEmpty()) {
                runCatching {
                    mapper.mapNextTracks(client.getPlaylistQueue(candidate.removePrefix("VL"), authenticated = true))
                }.getOrDefault(emptyList())
            } else {
                emptyList()
            }
            val resolvedQueueTracks = queueTracks.ifEmpty { authenticatedQueueTracks }
            if (resolvedQueueTracks.isNotEmpty()) {
                val shell = authenticatedDetails ?: publicDetails
                return PlaylistDetails(
                    id = candidate,
                    title = shell?.title ?: "Playlist",
                    author = shell?.author,
                    thumbnails = shell?.thumbnails?.takeIf { it.isNotEmpty() } ?: resolvedQueueTracks.first().thumbnails,
                    tracks = resolvedQueueTracks
                )
            }
        }

        return null
    }

    private suspend fun refreshArtwork(details: PlaylistDetails) {
        if (details.tracks.isEmpty()) return

        _isRefreshingArtwork.value = true
        try {
            val fallbackAlbum = inferFallbackAlbum(details)

            val visibleTracks = artworkEnricher.enrichArtwork(
                tracks = details.tracks,
                fallbackAlbum = fallbackAlbum,
                limit = 18
            )
            updateDetails(details.id, visibleTracks, fallbackAlbum)

            val allTracks = artworkEnricher.enrichArtwork(
                tracks = visibleTracks,
                fallbackAlbum = fallbackAlbum,
                limit = 80
            )
            updateDetails(details.id, allTracks, fallbackAlbum)
        } finally {
            _isRefreshingArtwork.value = false
        }
    }

    private fun updateDetails(id: String, tracks: List<com.musicglass.app.youtubemusic.SongItem>, fallbackAlbum: AlbumInfo?) {
        val current = _playlistDetails.value ?: return
        if (current.id != id) return

        val headerThumbnails = resolveHeaderThumbnails(current, tracks, fallbackAlbum)
        _playlistDetails.value = current.copy(
            thumbnails = headerThumbnails,
            tracks = tracks
        )
    }

    private fun inferFallbackAlbum(details: PlaylistDetails): AlbumInfo? {
        val normalizedId = details.id.removePrefix("VL")
        val isExplicitPlaylistId = normalizedId == "LM" ||
            normalizedId.startsWith("PL") ||
            normalizedId.startsWith("RD")
        val mentionsPlaylist = details.author?.lowercase()?.contains("playlist") == true

        if (isExplicitPlaylistId || mentionsPlaylist) return null

        return AlbumInfo(
            name = details.title,
            browseId = details.id,
            thumbnails = details.thumbnails
        )
    }

    private fun resolveHeaderThumbnails(
        current: PlaylistDetails,
        tracks: List<com.musicglass.app.youtubemusic.SongItem>,
        fallbackAlbum: AlbumInfo?
    ): List<Thumbnail> {
        if (fallbackAlbum != null) {
            val albumThumbs = tracks.firstNotNullOfOrNull { track ->
                track.album?.thumbnails?.takeIf { it.isNotEmpty() }
            }
            if (!albumThumbs.isNullOrEmpty()) return albumThumbs

            val firstTrackThumbs = tracks.firstOrNull()?.thumbnails?.takeIf { it.isNotEmpty() }
            if (!firstTrackThumbs.isNullOrEmpty()) return firstTrackThumbs
        }

        if (current.thumbnails.isNotEmpty()) return current.thumbnails

        return tracks.firstOrNull()?.thumbnails ?: emptyList()
    }
}
