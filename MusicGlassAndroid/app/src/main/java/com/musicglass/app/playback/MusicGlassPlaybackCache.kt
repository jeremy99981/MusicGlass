package com.musicglass.app.playback

import android.content.Context
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

@UnstableApi
object MusicGlassPlaybackCache {
    private const val MAX_CACHE_BYTES = 256L * 1024L * 1024L

    @Volatile
    private var simpleCache: SimpleCache? = null

    fun dataSourceFactory(context: Context): CacheDataSource.Factory {
        val upstream = DefaultHttpDataSource.Factory()
            .setUserAgent("MusicGlass Android")
            .setConnectTimeoutMs(30_000)
            .setReadTimeoutMs(60_000)
            .setAllowCrossProtocolRedirects(true)

        return CacheDataSource.Factory()
            .setCache(cache(context.applicationContext))
            .setUpstreamDataSourceFactory(upstream)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
    }

    private fun cache(context: Context): SimpleCache {
        return simpleCache ?: synchronized(this) {
            simpleCache ?: SimpleCache(
                File(context.filesDir, "musicglass_player_cache"),
                LeastRecentlyUsedCacheEvictor(MAX_CACHE_BYTES),
                StandaloneDatabaseProvider(context)
            ).also { simpleCache = it }
        }
    }
}
