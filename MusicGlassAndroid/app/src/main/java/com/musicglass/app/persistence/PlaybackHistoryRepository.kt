package com.musicglass.app.persistence

import android.content.Context
import com.musicglass.app.youtubemusic.ItemType
import com.musicglass.app.youtubemusic.SongItem
import com.musicglass.app.youtubemusic.cleanedMusicGlassMetadata
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

object PlaybackHistoryRepository {
    private const val PREFS = "musicglass_playback_history"
    private const val KEY_HISTORY = "history"
    private const val MAX_HISTORY_COUNT = 100

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private var appContext: Context? = null

    private val _history = MutableStateFlow<List<SongItem>>(emptyList())
    val history: StateFlow<List<SongItem>> = _history

    fun init(context: Context) {
        appContext = context.applicationContext
        _history.value = readStoredHistory()
    }

    fun add(track: SongItem) {
        if (track.type != ItemType.SONG || track.id.isBlank()) return

        val cleanedTrack = track.cleanedMusicGlassMetadata()
        val current = _history.value
        val updated = (listOf(cleanedTrack) + current.filterNot { it.id == cleanedTrack.id })
            .map { it.cleanedMusicGlassMetadata() }
            .take(MAX_HISTORY_COUNT)

        _history.value = updated
        appContext
            ?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            ?.edit()
            ?.putString(KEY_HISTORY, json.encodeToString(updated))
            ?.apply()
    }

    fun recentlyPlayed(): List<SongItem> = _history.value

    private fun readStoredHistory(): List<SongItem> {
        val raw = appContext
            ?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            ?.getString(KEY_HISTORY, null)
            ?: return emptyList()

        return runCatching {
            json.decodeFromString<List<SongItem>>(raw)
                .map { it.cleanedMusicGlassMetadata() }
        }.getOrDefault(emptyList())
    }
}
