package com.musicglass.app.youtubemusic

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.IOException

data class LyricLine(
    val time: Long, // in seconds or milliseconds. Let's use Double for seconds.
    val text: String
)

data class Lyrics(
    val plainText: String,
    val syncedLines: List<LyricLine>,
    val provider: String,
    val language: String?
)

class LyricsService {
    private val client = OkHttpClient()

    suspend fun getLyrics(
        title: String,
        artistName: String?,
        albumName: String?,
        durationSeconds: Double?
    ): Lyrics? = withContext(Dispatchers.IO) {
        if (title.isBlank()) return@withContext null

        val urlBuilder = okhttp3.HttpUrl.Builder()
            .scheme("https")
            .host("lrclib.net")
            .addPathSegment("api")
            .addPathSegment("get")
            .addQueryParameter("track_name", title)

        artistName?.takeIf { it.isNotBlank() }?.let { urlBuilder.addQueryParameter("artist_name", it) }
        albumName?.takeIf { it.isNotBlank() }?.let { urlBuilder.addQueryParameter("album_name", it) }
        durationSeconds?.let { urlBuilder.addQueryParameter("duration", Math.round(it).toString()) }

        val request = Request.Builder()
            .url(urlBuilder.build())
            .header("User-Agent", "MusicGlass/1.0 (third-party music client)")
            .build()

        try {
            val firstTryJson = client.newCall(request).execute().use { response ->
                if (response.isSuccessful) {
                    val body = response.body?.string()
                    if (!body.isNullOrBlank()) JSONObject(body) else null
                } else null
            }

            val json = firstTryJson ?: run {
                // Fallback to /api/search
                val query = "$title ${artistName ?: ""}".trim()
                val searchUrl = okhttp3.HttpUrl.Builder()
                    .scheme("https")
                    .host("lrclib.net")
                    .addPathSegment("api")
                    .addPathSegment("search")
                    .addQueryParameter("q", query)
                    .build()
                
                val searchRequest = Request.Builder()
                    .url(searchUrl)
                    .header("User-Agent", "MusicGlass/1.0 (third-party music client)")
                    .build()
                
                client.newCall(searchRequest).execute().use { response ->
                    if (!response.isSuccessful) return@withContext null
                    val body = response.body?.string() ?: return@withContext null
                    val array = org.json.JSONArray(body)
                    if (array.length() > 0) array.getJSONObject(0) else null
                }
            } ?: return@withContext null

                val syncedLyricsStr = json.optString("syncedLyrics", "").takeIf { it.isNotBlank() }
                val plainLyricsStr = json.optString("plainLyrics", "").takeIf { it.isNotBlank() }
                val lang = json.optString("lang", "").takeIf { it.isNotBlank() }

                val synced = parseSyncedLyrics(syncedLyricsStr)
                val plain = plainLyricsStr ?: synced.joinToString("\n") { it.text }

                if (plain.trim().isEmpty()) return@withContext null

                Lyrics(
                    plainText = plain,
                    syncedLines = synced,
                    provider = "LRCLib",
                    language = lang
                )
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun parseSyncedLyrics(text: String?): List<LyricLine> {
        if (text.isNullOrBlank()) return emptyList()
        return text.split("\n").mapNotNull { line ->
            val trimmed = line.trim()
            if (!trimmed.startsWith("[")) return@mapNotNull null
            val end = trimmed.indexOf("]")
            if (end == -1) return@mapNotNull null
            val timeCode = trimmed.substring(1, end)
            val body = trimmed.substring(end + 1).trim()
            if (body.isEmpty()) return@mapNotNull null
            val time = parseTimeCode(timeCode) ?: return@mapNotNull null
            LyricLine(time, body)
        }
    }

    private fun parseTimeCode(code: String): Long? {
        val parts = code.split(":")
        if (parts.size != 2) return null
        val minutes = parts[0].toDoubleOrNull() ?: return null
        val seconds = parts[1].toDoubleOrNull() ?: return null
        return (minutes * 60 + seconds).toLong()
    }
}
