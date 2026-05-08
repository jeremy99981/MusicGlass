package com.musicglass.app.playback

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import com.musicglass.app.persistence.PlaybackHistoryRepository
import com.musicglass.app.youtubemusic.ArtworkEnricher
import com.musicglass.app.youtubemusic.InnerTubeClient
import com.musicglass.app.youtubemusic.InnerTubeJSONMapper
import com.musicglass.app.youtubemusic.PlayerPayload
import com.musicglass.app.youtubemusic.SongItem
import com.musicglass.app.youtubemusic.ItemType
import com.musicglass.app.youtubemusic.bestThumbnailUrl
import com.musicglass.app.youtubemusic.cleanedMusicGlassMetadata
import com.musicglass.app.youtubemusic.isSameQueueItemAs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import kotlin.math.min

enum class RepeatMode {
    OFF,
    ONE,
    ALL;

    fun next(): RepeatMode = when (this) {
        OFF -> ONE
        ONE -> ALL
        ALL -> OFF
    }
}

private data class PlaybackRequest(
    val videoId: String,
    val title: String?,
    val artist: String?,
    val startPositionMs: Long,
    val resumeWhenReady: Boolean,
    val generation: Long
)

private data class AudioStream(
    val url: String,
    val isHls: Boolean,
    val expiresAtMs: Long
)

private data class PreloadedPlayback(
    val videoId: String,
    val payload: PlayerPayload,
    val expiresAtMs: Long
)

@OptIn(UnstableApi::class)
class MusicGlassPlaybackController private constructor(context: Context) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val innerTubeClient = InnerTubeClient()
    private val mapper = InnerTubeJSONMapper()
    private val artworkEnricher = ArtworkEnricher(innerTubeClient, mapper)
    private val connectivityObserver = NetworkConnectivityObserver(appContext)

    val exoPlayer: ExoPlayer = ExoPlayer.Builder(appContext)
        .setMediaSourceFactory(
            DefaultMediaSourceFactory(
                MusicGlassPlaybackCache.dataSourceFactory(appContext)
            )
        )
        .build()
        .apply {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                .build()
            setAudioAttributes(audioAttributes, true)
            setHandleAudioBecomingNoisy(true)
            volume = 1f
        }

    private val _currentTrack = MutableStateFlow<PlayerPayload?>(null)
    val currentTrack: StateFlow<PlayerPayload?> = _currentTrack

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private val _recoveryStatus = MutableStateFlow<String?>(null)
    val recoveryStatus: StateFlow<String?> = _recoveryStatus

    private val _isNetworkConnected = MutableStateFlow(connectivityObserver.isCurrentlyConnected())
    val isNetworkConnected: StateFlow<Boolean> = _isNetworkConnected

    // Keep track of song info for display in mini player even during fallback
    private val _currentSongInfo = MutableStateFlow<SongItem?>(null)
    val currentSongInfo: StateFlow<SongItem?> = _currentSongInfo

    private val _positionMs = MutableStateFlow(0L)
    val positionMs: StateFlow<Long> = _positionMs

    private val _durationMs = MutableStateFlow(0L)
    val durationMs: StateFlow<Long> = _durationMs

    private val _volume = MutableStateFlow(1f)
    val volume: StateFlow<Float> = _volume

    private val _repeatMode = MutableStateFlow(RepeatMode.OFF)
    val repeatMode: StateFlow<RepeatMode> = _repeatMode

    private val _shuffleEnabled = MutableStateFlow(false)
    val shuffleEnabled: StateFlow<Boolean> = _shuffleEnabled

    private val _canSkipNext = MutableStateFlow(false)
    val canSkipNext: StateFlow<Boolean> = _canSkipNext

    private val _canSkipPrevious = MutableStateFlow(false)
    val canSkipPrevious: StateFlow<Boolean> = _canSkipPrevious

    private val _queue = MutableStateFlow<List<SongItem>>(emptyList())
    val queue: StateFlow<List<SongItem>> = _queue

    private val _currentQueueIndex = MutableStateFlow<Int?>(null)
    val currentQueueIndex: StateFlow<Int?> = _currentQueueIndex

    val upcomingTracks = combine(_queue, _currentQueueIndex) { q, index ->
        if (index == null || q.isEmpty() || index >= q.lastIndex) {
            emptyList<SongItem>()
        } else {
            q.subList(index + 1, q.size)
        }
    }.stateIn(scope, SharingStarted.WhileSubscribed(5000), emptyList())

    private var isResolvingPlayback = false
    private var relatedQueueJob: Job? = null
    private var recoveryJob: Job? = null
    private var preloadJob: Job? = null
    private var transientRetryCount = 0
    private var playbackGeneration = 0L
    private var lastPlaybackRequest: PlaybackRequest? = null
    private val streamUrlCache = mutableMapOf<String, AudioStream>()
    private var preloadedPlayback: PreloadedPlayback? = null

    companion object {
        private const val TAG = "MusicGlassPlayback"
        private const val STREAM_URL_TTL_MS = 30 * 60 * 1000L
        private const val MAX_TRANSIENT_RETRIES = 7
        private const val REFRESH_STREAM_AFTER_RETRY = 3

        @Volatile
        private var instance: MusicGlassPlaybackController? = null

        fun get(context: Context): MusicGlassPlaybackController {
            return instance ?: synchronized(this) {
                instance ?: MusicGlassPlaybackController(context.applicationContext)
                    .also { instance = it }
            }
        }
    }

    init {
        PlaybackHistoryRepository.init(appContext)

        scope.launch {
            innerTubeClient.ensureVisitorData()
        }

        scope.launch {
            connectivityObserver.networkStatus.collect { isConnected ->
                _isNetworkConnected.value = isConnected
                if (!isConnected && hasActivePlayback()) {
                    _error.value = null
                    _recoveryStatus.value = "En attente du réseau"
                    _isLoading.value = true
                } else if (isConnected && _recoveryStatus.value != null) {
                    scheduleTransientRecovery(forceStreamRefresh = transientRetryCount >= REFRESH_STREAM_AFTER_RETRY)
                }
            }
        }

        _volume.value = exoPlayer.volume

        scope.launch {
            while (isActive) {
                updateProgressState()
                delay(500)
            }
        }

        exoPlayer.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                _isPlaying.value = isPlaying
                if (isPlaying) {
                    _isLoading.value = false
                }
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        _isLoading.value = true
                    }
                    Player.STATE_READY -> {
                        isResolvingPlayback = false
                        transientRetryCount = 0
                        _recoveryStatus.value = null
                        _error.value = null
                        _isLoading.value = false
                        updateProgressState()
                        scheduleNextTrackPreload()
                    }
                    Player.STATE_ENDED -> {
                        isResolvingPlayback = false
                        _isLoading.value = false
                        handleTrackEnded()
                    }
                    Player.STATE_IDLE -> {
                        if (!isResolvingPlayback) {
                            _isLoading.value = false
                        }
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.e(TAG, "ExoPlayer error: ${error.message}", error)
                if (isRecoverablePlaybackError(error)) {
                    handleTransientPlaybackError(error)
                    return
                }
                _recoveryStatus.value = null
                _error.value = error.message ?: "Lecture impossible"
                isResolvingPlayback = false
                _isLoading.value = false
                updateProgressState()
            }
        })
    }

    /**
     * Play a video by its ID. If the player returns LOGIN_REQUIRED or UNPLAYABLE,
     * fall back to searching for the same song (like the iOS version does).
     */
    @OptIn(UnstableApi::class)
    fun playVideo(
        videoId: String,
        songTitle: String? = null,
        songArtist: String? = null,
        startPositionMs: Long = 0L,
        forceStreamRefresh: Boolean = false,
        resumeWhenReady: Boolean = true
    ) {
        MusicGlassMediaSessionService.start(appContext)
        val requestGeneration = if (forceStreamRefresh) {
            playbackGeneration.takeIf { it > 0L } ?: (++playbackGeneration)
        } else {
            ++playbackGeneration
        }
        scope.launch {
            if (requestGeneration != playbackGeneration) return@launch
            isResolvingPlayback = true
            _isLoading.value = true
            _error.value = null
            _recoveryStatus.value = if (forceStreamRefresh) "Reconnexion..." else null
            lastPlaybackRequest = PlaybackRequest(
                videoId = videoId,
                title = songTitle,
                artist = songArtist,
                startPositionMs = startPositionMs.coerceAtLeast(0L),
                resumeWhenReady = resumeWhenReady,
                generation = requestGeneration
            )
            if (!forceStreamRefresh) {
                transientRetryCount = 0
                recoveryJob?.cancel()
            }
            if (forceStreamRefresh) {
                streamUrlCache.remove(videoId)
                if (preloadedPlayback?.videoId == videoId) {
                    preloadedPlayback = null
                }
            }

            try {
                innerTubeClient.ensureVisitorData()
                if (!isCurrentPlaybackRequest(requestGeneration, videoId)) return@launch

                consumePreloadedPlayback(videoId)?.let { preloaded ->
                    startPlayback(preloaded.payload, startPositionMs, resumeWhenReady, requestGeneration)
                    return@launch
                }

                // --- Attempt 1: Direct play with ANDROID_VR ---
                val resolution = resolvePlayback(videoId)
                if (!isCurrentPlaybackRequest(requestGeneration, videoId)) return@launch
                if (resolution != null) {
                    startPlayback(resolution, startPositionMs, resumeWhenReady, requestGeneration)
                    return@launch
                }

                // --- Attempt 2: Try with TV embedded client (no login required) ---
                // This fallback endpoint is often rejected by YouTube now ("device not supported"),
                // but we keep it as a best-effort before search fallback.
                Log.d(TAG, "ANDROID_VR failed, trying TV_EMBEDDED for $videoId")
                val tvResolution = resolvePlaybackTV(videoId)
                if (!isCurrentPlaybackRequest(requestGeneration, videoId)) return@launch
                if (tvResolution != null) {
                    startPlayback(tvResolution, startPositionMs, resumeWhenReady, requestGeneration)
                    return@launch
                }

                // --- Attempt 3: Fallback search (like iOS) ---
                val title = songTitle ?: _currentTrack.value?.title
                val artist = songArtist ?: _currentTrack.value?.author
                if (title != null) {
                    Log.d(TAG, "Direct play failed, searching for fallback: $title $artist")
                    val fallback = findPlayableFallback(videoId, title, artist ?: "")
                    if (!isCurrentPlaybackRequest(requestGeneration, videoId)) return@launch
                    if (fallback != null) {
                        startPlayback(fallback, startPositionMs, resumeWhenReady, requestGeneration)
                        return@launch
                    }
                }

                if (!connectivityObserver.isCurrentlyConnected()) {
                    handleTransientResolveFailure(requestGeneration, videoId)
                } else {
                    _recoveryStatus.value = null
                    _error.value = "Lecture impossible"
                }
                Log.e(TAG, "All playback attempts failed for $videoId")
            } catch (e: Exception) {
                if (!isCurrentPlaybackRequest(requestGeneration, videoId)) return@launch
                Log.e(TAG, "Error playing video: ${e.message}", e)
                if (isRecoverableThrowable(e)) {
                    handleTransientResolveFailure(requestGeneration, videoId)
                } else {
                    _recoveryStatus.value = null
                    _error.value = e.message ?: "Erreur inconnue"
                }
            } finally {
                if (isCurrentPlaybackRequest(requestGeneration, videoId) && _error.value != null) {
                    isResolvingPlayback = false
                    _isLoading.value = false
                }
            }
        }
    }

    private fun hasActivePlayback(): Boolean {
        return _currentTrack.value != null ||
            _currentSongInfo.value != null ||
            exoPlayer.currentMediaItem != null
    }

    private fun consumePreloadedPlayback(videoId: String): PreloadedPlayback? {
        val preload = preloadedPlayback ?: return null
        if (preload.videoId != videoId || preload.expiresAtMs <= System.currentTimeMillis()) {
            if (preload.videoId == videoId) preloadedPlayback = null
            return null
        }
        preloadedPlayback = null
        Log.d(TAG, "Using preloaded playback for $videoId")
        return preload
    }

    private fun isCurrentPlaybackRequest(generation: Long, videoId: String? = null): Boolean {
        if (generation != playbackGeneration) return false
        val request = lastPlaybackRequest
        return videoId == null || request == null || request.videoId == videoId
    }

    private fun handleTransientResolveFailure(generation: Long, videoId: String) {
        if (!isCurrentPlaybackRequest(generation, videoId)) return
        isResolvingPlayback = false
        _error.value = null
        _recoveryStatus.value = if (connectivityObserver.isCurrentlyConnected()) {
            "Reconnexion..."
        } else {
            "En attente du réseau"
        }
        _isLoading.value = true
        if (connectivityObserver.isCurrentlyConnected()) {
            scheduleTransientRecovery(
                forceStreamRefresh = true,
                expectedGeneration = generation,
                expectedVideoId = videoId
            )
        }
    }

    private fun handleTransientPlaybackError(error: PlaybackException) {
        val request = lastPlaybackRequest
        val currentVideoId = request?.videoId ?: _currentTrack.value?.videoId
        val generation = request?.generation ?: playbackGeneration
        Log.w(TAG, "Recoverable playback error for $currentVideoId: code=${error.errorCode}, message=${error.message}")
        if (!isCurrentPlaybackRequest(generation, currentVideoId)) return
        isResolvingPlayback = false
        _error.value = null
        _recoveryStatus.value = if (connectivityObserver.isCurrentlyConnected()) {
            "Reconnexion..."
        } else {
            "En attente du réseau"
        }
        _isLoading.value = true
        updateProgressState()

        val forceStreamRefresh = isExpiredStreamError(error) ||
            transientRetryCount >= REFRESH_STREAM_AFTER_RETRY
        scheduleTransientRecovery(
            forceStreamRefresh = forceStreamRefresh,
            expectedGeneration = generation,
            expectedVideoId = currentVideoId
        )
    }

    private fun scheduleTransientRecovery(
        forceStreamRefresh: Boolean,
        expectedGeneration: Long = lastPlaybackRequest?.generation ?: playbackGeneration,
        expectedVideoId: String? = lastPlaybackRequest?.videoId
    ) {
        recoveryJob?.cancel()

        if (!isCurrentPlaybackRequest(expectedGeneration, expectedVideoId)) return

        if (transientRetryCount >= MAX_TRANSIENT_RETRIES) {
            _recoveryStatus.value = null
            _isLoading.value = false
            _error.value = "Lecture impossible"
            transientRetryCount = 0
            return
        }

        recoveryJob = scope.launch {
            if (!isCurrentPlaybackRequest(expectedGeneration, expectedVideoId)) return@launch
            if (!connectivityObserver.isCurrentlyConnected()) {
                _recoveryStatus.value = "En attente du réseau"
                return@launch
            }

            transientRetryCount += 1
            _recoveryStatus.value = "Reconnexion..."
            val delayMs = min(1_000L * transientRetryCount, 5_000L)
            delay(delayMs)
            if (!isCurrentPlaybackRequest(expectedGeneration, expectedVideoId)) return@launch
            retryCurrentPlayback(
                forceStreamRefresh || transientRetryCount >= REFRESH_STREAM_AFTER_RETRY,
                expectedGeneration,
                expectedVideoId
            )
        }
    }

    private fun retryCurrentPlayback(
        forceStreamRefresh: Boolean,
        expectedGeneration: Long,
        expectedVideoId: String?
    ) {
        if (!isCurrentPlaybackRequest(expectedGeneration, expectedVideoId)) return
        val request = lastPlaybackRequest
        val resumeWhenReady = request?.resumeWhenReady ?: exoPlayer.playWhenReady || _isPlaying.value
        val resumePosition = exoPlayer.currentPosition
            .takeIf { it > 0L }
            ?: _positionMs.value.takeIf { it > 0L }
            ?: request?.startPositionMs
            ?: 0L

        if (!forceStreamRefresh && exoPlayer.currentMediaItem != null) {
            runCatching {
                exoPlayer.prepare()
                exoPlayer.playWhenReady = resumeWhenReady
            }.onFailure {
                Log.w(TAG, "Direct ExoPlayer retry failed: ${it.message}", it)
                if (!isCurrentPlaybackRequest(expectedGeneration, expectedVideoId)) return@onFailure
                request?.let { playbackRequest ->
                    playVideo(
                        videoId = playbackRequest.videoId,
                        songTitle = playbackRequest.title,
                        songArtist = playbackRequest.artist,
                        startPositionMs = resumePosition,
                        forceStreamRefresh = true,
                        resumeWhenReady = resumeWhenReady
                    )
                }
            }
            return
        }

        if (request != null) {
            if (!isCurrentPlaybackRequest(expectedGeneration, request.videoId)) return
            streamUrlCache.remove(request.videoId)
            playVideo(
                videoId = request.videoId,
                songTitle = request.title,
                songArtist = request.artist,
                startPositionMs = resumePosition,
                forceStreamRefresh = true,
                resumeWhenReady = resumeWhenReady
            )
        } else if (exoPlayer.currentMediaItem != null) {
            exoPlayer.prepare()
            exoPlayer.playWhenReady = resumeWhenReady
        }
    }

    private fun isRecoverablePlaybackError(error: PlaybackException): Boolean {
        return !connectivityObserver.isCurrentlyConnected() ||
            error.errorCode in setOf(
                PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
                PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
                PlaybackException.ERROR_CODE_TIMEOUT,
                PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS,
                PlaybackException.ERROR_CODE_IO_UNSPECIFIED,
                PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND,
                PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE
            ) ||
            isRecoverableThrowable(error.cause)
    }

    private fun isExpiredStreamError(error: PlaybackException): Boolean {
        val message = listOfNotNull(error.message, error.cause?.message)
            .joinToString(" ")
            .lowercase()
        return error.errorCode == PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS ||
            message.contains("403") ||
            message.contains("410") ||
            message.contains("expired") ||
            message.contains("forbidden")
    }

    private fun isRecoverableThrowable(throwable: Throwable?): Boolean {
        return when (throwable) {
            null -> !connectivityObserver.isCurrentlyConnected()
            is ConnectException,
            is UnknownHostException,
            is SocketTimeoutException -> true
            else -> isRecoverableThrowable(throwable.cause)
        }
    }

    /**
     * Play a SongItem — preserves title/artist info for the mini player and fallback search.
     */
    fun playSongItem(item: SongItem, queueItems: List<SongItem> = emptyList()) {
        val cleanedItem = item.cleanedMusicGlassMetadata()
        val sanitizedQueue = queueItems
            .filter { it.type == ItemType.SONG }
            .map { it.cleanedMusicGlassMetadata() }
            .distinctBy { it.id }

        if (sanitizedQueue.isNotEmpty()) {
            _queue.value = sanitizedQueue
            _currentQueueIndex.value = sanitizedQueue.indexOfFirst { it.id == cleanedItem.id }.takeIf { it >= 0 } ?: 0
        } else {
            _queue.value = listOf(cleanedItem)
            _currentQueueIndex.value = 0
        }

        _currentSongInfo.value = cleanedItem
        updateQueueCapabilities()
        val artist = cleanedItem.artists.firstOrNull()?.name
        playVideo(cleanedItem.id, songTitle = cleanedItem.title, songArtist = artist)

        if (sanitizedQueue.size <= 1) {
            scheduleRelatedQueue(cleanedItem)
        }
    }

    fun playRadio(item: SongItem) {
        val cleanedItem = item.cleanedMusicGlassMetadata()
        val currentItem = _currentSongInfo.value?.cleanedMusicGlassMetadata()
        if (currentItem != null && currentItem.isSameQueueItemAs(cleanedItem)) {
            val currentQueue = _queue.value
            val currentIndex = _currentQueueIndex.value
            if (currentIndex == null || currentQueue.getOrNull(currentIndex)?.isSameQueueItemAs(currentItem) != true) {
                _queue.value = listOf(currentItem)
                _currentQueueIndex.value = 0
            }
            _currentSongInfo.value = currentItem
            updateQueueCapabilities()
            scheduleRelatedQueue(currentItem, forceRadio = true, replaceUpcoming = true)
            Log.d(TAG, "Refreshing radio queue without restarting ${currentItem.title} (${currentItem.id})")
            return
        }

        _queue.value = listOf(cleanedItem)
        _currentQueueIndex.value = 0
        _currentSongInfo.value = cleanedItem
        updateQueueCapabilities()

        val artist = cleanedItem.artists.firstOrNull()?.name
        playVideo(cleanedItem.id, songTitle = cleanedItem.title, songArtist = artist)
        scheduleRelatedQueue(cleanedItem, forceRadio = true, replaceUpcoming = true)
    }

    private fun handleTrackEnded() {
        if (_repeatMode.value == RepeatMode.ONE) {
            seekTo(0L)
            exoPlayer.play()
            return
        }
        next(fromAutoAdvance = true)
    }

    /**
     * Try to resolve playback with the ANDROID_VR client.
     */
    private suspend fun resolvePlayback(videoId: String): PlayerPayload? {
        return try {
            val jsonResponse = innerTubeClient.getPlayerPayload(videoId)
            val rawPayload = mapper.mapPlayerPayload(jsonResponse, videoId) ?: return null
            val payload = enrichPayloadMetadata(rawPayload)
            val url = bestAudioUrl(payload)
            Log.d(TAG, "VR: status=${payload.playabilityStatus}, formats=${payload.formats.size}, hasUrl=${url != null}, reason=${payload.reason}")
            if (payload.playabilityStatus == "OK" && url != null) {
                payload
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "VR player request failed: ${e.message}")
            null
        }
    }

    /**
     * Try to resolve playback with the TV embedded client (bypasses login requirement).
     */
    private suspend fun resolvePlaybackTV(videoId: String): PlayerPayload? {
        return try {
            val jsonResponse = innerTubeClient.getPlayerPayloadTV(videoId)
            val rawPayload = mapper.mapPlayerPayload(jsonResponse, videoId) ?: return null
            val payload = enrichPayloadMetadata(rawPayload)
            val url = bestAudioUrl(payload)
            Log.d(TAG, "TV: status=${payload.playabilityStatus}, formats=${payload.formats.size}, hasUrl=${url != null}, reason=${payload.reason}")
            if (payload.playabilityStatus == "OK" && url != null) {
                payload
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "TV player request failed: ${e.message}")
            null
        }
    }

    /**
     * Search for the same song and try to find a playable version.
     * This mirrors the iOS `playableFallbackTrack` method.
     */
    private suspend fun findPlayableFallback(
        originalVideoId: String,
        title: String,
        artist: String
    ): PlayerPayload? {
        val queries = listOf(
            "$title $artist",
            title
        ).filter { it.isNotBlank() }.distinct()

        for (query in queries) {
            try {
                // "EgWKAQIIAWoMEAMQBBAJEA4QChAF" is the YouTube Music filter for "Songs"
                val searchJson = innerTubeClient.search(query, params = "EgWKAQIIAWoMEAMQBBAJEA4QChAF")
                val searchResults = mapper.mapSearchResults(searchJson)

                // Filter candidates: songs that look like the same track
                val candidates = searchResults
                    .filter { it.type == ItemType.SONG }
                    .filter { it.id != originalVideoId }
                    .filter { looksLikeSameSong(it, title, artist) }
                    .take(6)

                for (candidate in candidates) {
                    Log.d(TAG, "Trying fallback: ${candidate.title} (${candidate.id})")
                    
                    // Try VR client first
                    val vrPayload = resolvePlayback(candidate.id)
                    if (vrPayload != null) {
                        // Enrich with original info
                        return vrPayload.copy(title = title, author = artist.ifEmpty { vrPayload.author })
                    }

                    // Then try TV client
                    val tvPayload = resolvePlaybackTV(candidate.id)
                    if (tvPayload != null) {
                        return tvPayload.copy(title = title, author = artist.ifEmpty { tvPayload.author })
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Fallback search failed for query '$query': ${e.message}")
            }
        }
        return null
    }

    /**
     * Check if a search result looks like the same song (similar to iOS's musicGlassLooksLikeSameSong).
     */
    private fun looksLikeSameSong(candidate: SongItem, originalTitle: String, originalArtist: String): Boolean {
        val candidateTitle = candidate.title.normalize()
        val origTitle = originalTitle.normalize()
        
        if (candidateTitle.isEmpty() || origTitle.isEmpty()) return false
        
        // Title must match loosely
        if (!candidateTitle.contains(origTitle) && !origTitle.contains(candidateTitle)) return false

        // If we have artist info, check it matches
        if (originalArtist.isNotBlank()) {
            val origArtistNorm = originalArtist.normalize()
            val candidateArtist = candidate.artists.joinToString(" ") { it.name }.normalize()
            if (candidateArtist.isNotBlank() && !candidateArtist.contains(origArtistNorm) && !origArtistNorm.contains(candidateArtist)) {
                return false
            }
        }
        return true
    }

    private fun String.normalize(): String {
        return this.lowercase()
            .replace(Regex("\\s*[\\(\\[].*?[\\)\\]]"), "") // Remove parenthetical
            .trim()
    }

    private fun enrichPayloadMetadata(payload: PlayerPayload): PlayerPayload {
        val fallback = _currentSongInfo.value
        val fallbackTitle = fallback?.title?.trim().orEmpty()
        val fallbackArtist = fallback?.artists
            ?.joinToString(", ") { it.name.trim() }
            ?.takeIf { it.isNotBlank() }
        val fallbackThumbnails = when {
            fallback?.album?.thumbnails?.isNotEmpty() == true -> fallback.album.thumbnails
            fallback?.thumbnails?.isNotEmpty() == true -> fallback.thumbnails
            else -> emptyList()
        }

        return payload.copy(
            title = if (fallbackTitle.isNotEmpty()) fallbackTitle else payload.title,
            author = fallbackArtist ?: payload.author,
            thumbnails = if (fallbackThumbnails.isNotEmpty()) fallbackThumbnails else payload.thumbnails
        )
    }

    private suspend fun enrichedCurrentSongInfo(payload: PlayerPayload): SongItem? {
        val fallback = _currentSongInfo.value
        val payloadArtists = payload.author
            ?.split(",", "&")
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() }
            ?.map { com.musicglass.app.youtubemusic.ArtistInfo(name = it) }
            .orEmpty()

        val base = when {
            fallback != null -> fallback.copy(
                title = fallback.title.ifBlank { payload.title },
                artists = fallback.artists.ifEmpty { payloadArtists },
                thumbnails = payload.thumbnails.ifEmpty { fallback.thumbnails },
                album = fallback.album?.let { album ->
                    if (album.thumbnails.isEmpty() && payload.thumbnails.isNotEmpty()) {
                        album.copy(thumbnails = payload.thumbnails)
                    } else {
                        album
                    }
                }
            )
            payload.videoId.isNotBlank() -> SongItem(
                id = payload.videoId,
                type = ItemType.SONG,
                title = payload.title,
                artists = payloadArtists,
                album = null,
                thumbnails = payload.thumbnails
            )
            else -> null
        } ?: return null

        return runCatching {
            artworkEnricher.enrichArtwork(listOf(base), fallbackAlbum = base.album, limit = 1).firstOrNull()
        }.getOrNull() ?: base
    }

    /**
     * Get the best audio URL from a player payload (prefers audio/mp4, highest bitrate).
     */
    private fun bestAudioStream(payload: PlayerPayload): AudioStream? {
        streamUrlCache[payload.videoId]?.takeIf { it.expiresAtMs > System.currentTimeMillis() }?.let {
            return it
        }

        val directAudio = payload.formats
            .filter { it.mimeType.startsWith("audio/") && !it.url.isNullOrEmpty() }
            .sortedByDescending {
                val mp4Bonus = if (it.mimeType.contains("mp4")) 10_000_000 else 0
                mp4Bonus + it.bitrate
            }
            .firstOrNull()
            ?.url
        if (!directAudio.isNullOrEmpty()) return cacheStream(payload.videoId, directAudio, isHls = false)

        // Some responses expose progressive muxed streams instead of audio/*.
        val progressiveWithAudio = payload.formats
            .filter {
                !it.url.isNullOrEmpty() &&
                    (it.mimeType.contains("mp4a", ignoreCase = true) ||
                        (it.mimeType.contains("video/", ignoreCase = true) && it.mimeType.contains("mp4", ignoreCase = true)))
            }
            .sortedByDescending { it.bitrate }
            .firstOrNull()
            ?.url
        if (!progressiveWithAudio.isNullOrEmpty()) return cacheStream(payload.videoId, progressiveWithAudio, isHls = false)

        // Fallbacks observed on some payloads: HLS and server ABR URL.
        return when {
            !payload.hlsManifestUrl.isNullOrEmpty() -> cacheStream(payload.videoId, payload.hlsManifestUrl, isHls = true)
            !payload.serverAbrStreamingUrl.isNullOrEmpty() -> cacheStream(payload.videoId, payload.serverAbrStreamingUrl, isHls = false)
            else -> null
        }
    }

    private fun bestAudioUrl(payload: PlayerPayload): String? {
        return bestAudioStream(payload)?.url
    }

    private fun cacheStream(videoId: String, url: String, isHls: Boolean): AudioStream {
        val stream = AudioStream(
            url = url,
            isHls = isHls,
            expiresAtMs = System.currentTimeMillis() + STREAM_URL_TTL_MS
        )
        streamUrlCache[videoId] = stream
        return stream
    }

    private fun mediaMetadataFor(payload: PlayerPayload): MediaMetadata {
        val artwork = payload.thumbnails.bestThumbnailUrl()
            ?: _currentSongInfo.value?.album?.thumbnails?.bestThumbnailUrl()
            ?: _currentSongInfo.value?.thumbnails?.bestThumbnailUrl()
        return MediaMetadata.Builder()
            .setTitle(payload.title)
            .setArtist(payload.author)
            .setAlbumTitle(_currentSongInfo.value?.album?.name)
            .setArtworkUri(artwork?.let(Uri::parse))
            .build()
    }

    /**
     * Start playback with ExoPlayer.
     */
    @OptIn(UnstableApi::class)
    private fun startPlayback(
        payload: PlayerPayload,
        startPositionMs: Long = 0L,
        resumeWhenReady: Boolean = true,
        generation: Long = playbackGeneration
    ) {
        if (!isCurrentPlaybackRequest(generation)) return
        _currentTrack.value = payload
        scope.launch {
            enrichedCurrentSongInfo(payload)?.let { enriched ->
                if (!isCurrentPlaybackRequest(generation)) return@launch
                _currentSongInfo.value = enriched
                PlaybackHistoryRepository.add(enriched)
            }
        }
        _error.value = null
        _recoveryStatus.value = null
        _positionMs.value = startPositionMs.coerceAtLeast(0L)
        _durationMs.value = (payload.durationSeconds ?: 0L) * 1000L
        updateQueueCapabilities()

        val stream = bestAudioStream(payload)
        if (stream != null) {
            if (!isCurrentPlaybackRequest(generation)) return
            Log.d(TAG, "Playing: ${payload.title} by ${payload.author}")
            val metadata = mediaMetadataFor(payload)
            val mediaItem = if (stream.isHls) {
                MediaItem.Builder()
                    .setUri(stream.url)
                    .setMimeType(MimeTypes.APPLICATION_M3U8)
                    .setMediaId(payload.videoId)
                    .setMediaMetadata(metadata)
                    .build()
            } else {
                MediaItem.Builder()
                    .setUri(stream.url)
                    .setMediaId(payload.videoId)
                    .setMediaMetadata(metadata)
                    .build()
            }
            exoPlayer.setMediaItem(mediaItem, startPositionMs.coerceAtLeast(0L))
            exoPlayer.prepare()
            exoPlayer.playWhenReady = resumeWhenReady
        } else {
            if (!isCurrentPlaybackRequest(generation)) return
            Log.e(TAG, "No playable URL found for ${payload.videoId}")
            isResolvingPlayback = false
            _error.value = "Aucun flux audio disponible"
        }
    }

    fun togglePlayPause() {
        if (exoPlayer.isPlaying) {
            exoPlayer.pause()
        } else {
            if (exoPlayer.playbackState == Player.STATE_IDLE && exoPlayer.currentMediaItem != null) {
                exoPlayer.prepare()
            }
            exoPlayer.play()
        }
    }

    fun seekTo(positionMs: Long) {
        val target = positionMs.coerceAtLeast(0L)
        exoPlayer.seekTo(target)
        _positionMs.value = target
        updateQueueCapabilities()
    }

    fun next(fromAutoAdvance: Boolean = false) {
        val q = _queue.value
        if (q.isEmpty()) return

        val nextIndex = when {
            _shuffleEnabled.value && q.size > 1 -> {
                val currentIndex = _currentQueueIndex.value
                q.indices
                    .filter { it != currentIndex }
                    .randomOrNull()
            }
            else -> {
                val currentIndex = _currentQueueIndex.value ?: -1
                val candidate = currentIndex + 1
                when {
                    candidate in q.indices -> candidate
                    _repeatMode.value == RepeatMode.ALL && q.isNotEmpty() -> 0
                    else -> null
                }
            }
        }

        if (nextIndex == null) {
            _isPlaying.value = false
            updateQueueCapabilities()
            return
        }

        _currentQueueIndex.value = nextIndex
        val nextItem = q[nextIndex]
        Log.d(TAG, "Playing next track: ${nextItem.title} (${nextItem.id}) auto=$fromAutoAdvance")
        playSongItem(nextItem, q)
    }

    fun previous() {
        if (_positionMs.value > 5_000L) {
            seekTo(0L)
            return
        }

        val q = _queue.value
        if (q.isEmpty()) return

        val previousIndex = when {
            _shuffleEnabled.value && q.size > 1 -> {
                val currentIndex = _currentQueueIndex.value
                q.indices
                    .filter { it != currentIndex }
                    .randomOrNull()
            }
            else -> {
                val currentIndex = _currentQueueIndex.value ?: 0
                val candidate = currentIndex - 1
                when {
                    candidate in q.indices -> candidate
                    _repeatMode.value == RepeatMode.ALL && q.isNotEmpty() -> q.lastIndex
                    else -> null
                }
            }
        }

        if (previousIndex == null) {
            seekTo(0L)
            updateQueueCapabilities()
            return
        }

        _currentQueueIndex.value = previousIndex
        val previousItem = q[previousIndex]
        Log.d(TAG, "Playing previous track: ${previousItem.title} (${previousItem.id})")
        playSongItem(previousItem, q)
    }

    fun playFromQueue(item: SongItem) {
        playSongItem(item, _queue.value)
    }

    private fun scheduleRelatedQueue(
        seed: SongItem,
        forceRadio: Boolean = false,
        replaceUpcoming: Boolean = false,
        replaceIncoming: Boolean = false
    ) {
        relatedQueueJob?.cancel()
        relatedQueueJob = scope.launch {
            val related = fetchRelatedTracks(seed, forceRadio)
            if (related.isEmpty()) return@launch

            val currentQueue = _queue.value
            val currentIndex = _currentQueueIndex.value ?: return@launch
            val current = currentQueue.getOrNull(currentIndex) ?: return@launch
            if (current.id != seed.id) return@launch

            val seenIds = mutableSetOf<String>()
            
            val baseQueue = if (replaceUpcoming || replaceIncoming) {
                currentQueue.subList(0, currentIndex + 1)
            } else {
                currentQueue
            }
            
            baseQueue.forEach { seenIds.add(it.id) }

            val additions = related
                .filter { it.id != seed.id }
                .filter { seenIds.add(it.id) }
                .take(24)
            
            if (additions.isEmpty() && !(replaceUpcoming || replaceIncoming)) return@launch

            _queue.value = baseQueue + additions
            updateQueueCapabilities()
            scheduleNextTrackPreload()
            Log.d(TAG, "Related queue ${if (replaceUpcoming || replaceIncoming) "replaced" else "appended"}: ${additions.size} tracks for ${seed.title}")
        }
    }

    private fun scheduleNextTrackPreload() {
        val q = _queue.value
        val index = _currentQueueIndex.value ?: return
        val nextItem = q.getOrNull(index + 1) ?: return
        if (nextItem.type != ItemType.SONG) return

        val now = System.currentTimeMillis()
        if (preloadedPlayback?.videoId == nextItem.id && preloadedPlayback?.expiresAtMs?.let { it > now } == true) {
            return
        }
        if (streamUrlCache[nextItem.id]?.expiresAtMs?.let { it > now } == true) {
            return
        }

        preloadJob?.cancel()
        preloadJob = scope.launch {
            val requestGeneration = playbackGeneration
            val preloaded = runCatching {
                resolvePreloadPlayback(nextItem.cleanedMusicGlassMetadata())
            }.onFailure {
                Log.d(TAG, "Next track preload failed for ${nextItem.id}: ${it.message}")
            }.getOrNull() ?: return@launch

            if (requestGeneration != playbackGeneration) return@launch
            val currentQueue = _queue.value
            val currentIndex = _currentQueueIndex.value ?: return@launch
            if (currentQueue.getOrNull(currentIndex + 1)?.id != nextItem.id) return@launch

            preloadedPlayback = preloaded
            Log.d(TAG, "Preloaded next track: ${nextItem.title} (${nextItem.id})")
        }
    }

    private suspend fun resolvePreloadPlayback(item: SongItem): PreloadedPlayback? {
        val payload = resolvePreloadPayload(item, useTvClient = false)
            ?: resolvePreloadPayload(item, useTvClient = true)
            ?: return null
        val stream = bestAudioStream(payload) ?: return null
        return PreloadedPlayback(
            videoId = item.id,
            payload = payload,
            expiresAtMs = min(stream.expiresAtMs, System.currentTimeMillis() + STREAM_URL_TTL_MS)
        )
    }

    private suspend fun resolvePreloadPayload(item: SongItem, useTvClient: Boolean): PlayerPayload? {
        val jsonResponse = if (useTvClient) {
            innerTubeClient.getPlayerPayloadTV(item.id)
        } else {
            innerTubeClient.getPlayerPayload(item.id)
        }
        val rawPayload = mapper.mapPlayerPayload(jsonResponse, item.id) ?: return null
        val artistLine = item.artists
            .joinToString(", ") { it.name.trim() }
            .takeIf { it.isNotBlank() }
        val thumbnails = when {
            item.album?.thumbnails?.isNotEmpty() == true -> item.album.thumbnails
            item.thumbnails.isNotEmpty() -> item.thumbnails
            else -> rawPayload.thumbnails
        }
        val payload = rawPayload.copy(
            title = item.title.ifBlank { rawPayload.title },
            author = artistLine ?: rawPayload.author,
            thumbnails = thumbnails
        )
        return if (payload.playabilityStatus == "OK" && bestAudioUrl(payload) != null) payload else null
    }

    private suspend fun fetchRelatedTracks(seed: SongItem, forceRadio: Boolean = false): List<SongItem> {
        val radioPlaylistId = "RDAMVM${seed.id}"
        val radioTracks = runCatching {
            mapper.mapNextTracks(innerTubeClient.getNext(seed.id, playlistId = radioPlaylistId))
                .asPlayableRecommendations(seed)
        }.getOrDefault(emptyList())

        if (forceRadio || radioTracks.size >= 6) {
            return radioTracks.take(30)
        }

        return runCatching {
            mapper.mapNextTracks(innerTubeClient.getNext(seed.id))
                .asPlayableRecommendations(seed)
                .take(30)
        }.getOrDefault(radioTracks)
    }

    private fun List<SongItem>.asPlayableRecommendations(seed: SongItem): List<SongItem> {
        val seedArtist = seed.artists.joinToString(" ") { it.name }.normalize()
        return this
            .filter { it.type == ItemType.SONG }
            .filter { it.id != seed.id }
            .filter { it.title.isNotBlank() }
            .filterNot {
                val folded = "${it.title} ${it.artists.joinToString(" ") { artist -> artist.name }}".normalize()
                folded.contains("podcast") || folded.contains("episode") || folded.contains("audiobook")
            }
            .filterNot {
                seedArtist.isNotBlank() &&
                    it.title.normalize() == seed.title.normalize() &&
                    it.artists.joinToString(" ") { artist -> artist.name }.normalize() == seedArtist
            }
            .distinctBy { it.id }
    }

    fun removeFromQueue(item: SongItem) {
        val currentQ = _queue.value.toMutableList()
        val indexToRemove = currentQ.indexOfFirst { it.id == item.id }
        if (indexToRemove >= 0) {
            currentQ.removeAt(indexToRemove)
            _queue.value = currentQ
            
            val currIndex = _currentQueueIndex.value ?: -1
            if (indexToRemove < currIndex) {
                _currentQueueIndex.value = currIndex - 1
            } else if (indexToRemove == currIndex) {
                if (currentQ.isNotEmpty()) {
                    val nextIndex = if (currIndex >= currentQ.size) 0 else currIndex
                    _currentQueueIndex.value = nextIndex
                    playSongItem(currentQ[nextIndex], currentQ)
                } else {
                    _currentQueueIndex.value = null
                    exoPlayer.stop()
                }
            }
            updateQueueCapabilities()
        }
    }

    fun cycleRepeatMode() {
        _repeatMode.value = _repeatMode.value.next()
        updateQueueCapabilities()
    }

    fun toggleShuffle() {
        _shuffleEnabled.value = !_shuffleEnabled.value
        updateQueueCapabilities()
    }

    fun setVolume(volume: Float) {
        val safeVolume = volume.coerceIn(0f, 1f)
        exoPlayer.volume = safeVolume
        _volume.value = safeVolume
    }

    private fun updateProgressState() {
        val currentPosition = exoPlayer.currentPosition.coerceAtLeast(0L)
        val playerDuration = exoPlayer.duration.takeIf { it > 0 } ?: 0L
        val payloadDuration = (_currentTrack.value?.durationSeconds ?: 0L) * 1000L
        _positionMs.value = currentPosition
        _durationMs.value = maxOf(playerDuration, payloadDuration)
        _volume.value = exoPlayer.volume
        updateQueueCapabilities()
    }

    private fun updateQueueCapabilities() {
        val q = _queue.value
        val hasPreviousItem = when {
            q.isEmpty() -> false
            _shuffleEnabled.value && q.size > 1 -> true
            else -> {
                val currentIndex = _currentQueueIndex.value ?: 0
                currentIndex > 0 || (_repeatMode.value == RepeatMode.ALL && q.size > 1)
            }
        }
        val hasNextItem = when {
            q.isEmpty() -> false
            _shuffleEnabled.value && q.size > 1 -> true
            else -> {
                val currentIndex = _currentQueueIndex.value ?: -1
                currentIndex < q.lastIndex || (_repeatMode.value == RepeatMode.ALL && q.size > 1)
            }
        }

        _canSkipPrevious.value = _positionMs.value > 5_000L || hasPreviousItem
        _canSkipNext.value = hasNextItem
    }

    fun release() {
        recoveryJob?.cancel()
        relatedQueueJob?.cancel()
        connectivityObserver.unregister()
        exoPlayer.release()
    }
}
