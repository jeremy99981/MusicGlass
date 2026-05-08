package com.musicglass.app.persistence

import com.musicglass.app.youtubemusic.SongItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class LibraryCache(
    val likedSongs: List<SongItem> = emptyList(),
    val playlists: List<SongItem> = emptyList(),
    val history: List<SongItem> = emptyList(),
    val lastUpdated: Long = 0L
)

object LibraryRepository {
    private val _cache = MutableStateFlow<LibraryCache?>(null)
    val cache: StateFlow<LibraryCache?> = _cache.asStateFlow()

    fun updateCache(likedSongs: List<SongItem>, playlists: List<SongItem>, history: List<SongItem>) {
        _cache.value = LibraryCache(
            likedSongs = likedSongs,
            playlists = playlists,
            history = history,
            lastUpdated = System.currentTimeMillis()
        )
    }

    fun clearCache() {
        _cache.value = null
    }

    fun getCachedData(): LibraryCache? = _cache.value
    
    fun hasCache(): Boolean = _cache.value != null
}
