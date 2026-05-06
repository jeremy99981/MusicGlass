package com.musicglass.app.playback

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import com.musicglass.app.youtubemusic.SongItem

class PlayerViewModel(application: Application) : AndroidViewModel(application) {
    private val controller = MusicGlassPlaybackController.get(application.applicationContext)

    val exoPlayer = controller.exoPlayer
    val currentTrack = controller.currentTrack
    val isPlaying = controller.isPlaying
    val isLoading = controller.isLoading
    val error = controller.error
    val recoveryStatus = controller.recoveryStatus
    val isNetworkConnected = controller.isNetworkConnected
    val currentSongInfo = controller.currentSongInfo
    val positionMs = controller.positionMs
    val durationMs = controller.durationMs
    val volume = controller.volume
    val repeatMode = controller.repeatMode
    val shuffleEnabled = controller.shuffleEnabled
    val canSkipNext = controller.canSkipNext
    val canSkipPrevious = controller.canSkipPrevious
    val queue = controller.queue
    val currentQueueIndex = controller.currentQueueIndex
    val upcomingTracks = controller.upcomingTracks

    fun playVideo(
        videoId: String,
        songTitle: String? = null,
        songArtist: String? = null,
        startPositionMs: Long = 0L,
        forceStreamRefresh: Boolean = false,
        resumeWhenReady: Boolean = true
    ) = controller.playVideo(
        videoId = videoId,
        songTitle = songTitle,
        songArtist = songArtist,
        startPositionMs = startPositionMs,
        forceStreamRefresh = forceStreamRefresh,
        resumeWhenReady = resumeWhenReady
    )

    fun playSongItem(item: SongItem, queueItems: List<SongItem> = emptyList()) =
        controller.playSongItem(item, queueItems)

    fun playRadio(item: SongItem) = controller.playRadio(item)

    fun playFromQueue(item: SongItem) = controller.playFromQueue(item)

    fun togglePlayPause() = controller.togglePlayPause()

    fun seekTo(positionMs: Long) = controller.seekTo(positionMs)

    fun next(fromAutoAdvance: Boolean = false) = controller.next(fromAutoAdvance)

    fun previous() = controller.previous()

    fun removeFromQueue(item: SongItem) = controller.removeFromQueue(item)

    fun cycleRepeatMode() = controller.cycleRepeatMode()

    fun toggleShuffle() = controller.toggleShuffle()

    fun setVolume(volume: Float) = controller.setVolume(volume)
}
