package com.musicglass.app.youtubemusic

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.ConnectionPool
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

class InnerTubeClient {
    companion object {
        @Volatile
        private var sharedVisitorData: String? = null

        private val sharedConnectionPool = ConnectionPool()
    }

    private var visitorData: String?
        get() = sharedVisitorData
        set(value) {
            sharedVisitorData = value
        }

    // WEB_REMIX client — used for browse, search, home
    private val webRemixClient = OkHttpClient.Builder()
        .connectionPool(sharedConnectionPool)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .addInterceptor { chain ->
            val original = chain.request()
            val requestBuilder = original.newBuilder()
                .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0")
                .header("Origin", "https://music.youtube.com")
                .header("X-Origin", "https://music.youtube.com")
                .header("Referer", "https://music.youtube.com/")
                .header("X-Goog-Api-Format-Version", "1")
                .header("X-YouTube-Client-Name", "67")
                .header("X-YouTube-Client-Version", "1.20260213.01.00")
            activeVisitorData()?.let { requestBuilder.header("X-Goog-Visitor-Id", it) }
            chain.proceed(requestBuilder.build())
        }
        .build()

    // ANDROID_VR client — used for player (returns direct audio URLs, no signature cipher)
    private val playerClient = OkHttpClient.Builder()
        .connectionPool(sharedConnectionPool)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .addInterceptor { chain ->
            val original = chain.request()
            val requestBuilder = original.newBuilder()
                .header("User-Agent", "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)")
                .header("X-Goog-Api-Format-Version", "1")
                .header("X-YouTube-Client-Name", "28")
                .header("X-YouTube-Client-Version", "1.43.32")
            activeVisitorData()?.let { requestBuilder.header("X-Goog-Visitor-Id", it) }
            chain.proceed(requestBuilder.build())
        }
        .build()

    // TV_EMBEDDED client — fallback for content requiring login
    private val tvClient = OkHttpClient.Builder()
        .connectionPool(sharedConnectionPool)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .addInterceptor { chain ->
            val original = chain.request()
            val requestBuilder = original.newBuilder()
                .header("User-Agent", "Mozilla/5.0")
                .header("X-Goog-Api-Format-Version", "1")
                .header("X-YouTube-Client-Name", "85")
                .header("X-YouTube-Client-Version", "2.0")
            activeVisitorData()?.let { requestBuilder.header("X-Goog-Visitor-Id", it) }
            chain.proceed(requestBuilder.build())
        }
        .build()

    private val json = Json { 
        ignoreUnknownKeys = true 
        isLenient = true
        encodeDefaults = true
    }
    
    private val mediaType = "application/json; charset=utf-8".toMediaType()

    private fun activeVisitorData(): String? = visitorData ?: AuthService.state.value.visitorData

    private fun webRemixContext(includeLogin: Boolean = false) = InnerTubeContext(
        client = InnerTubeClientInfo(
            visitorData = activeVisitorData()
        ),
        user = InnerTubeUserInfo(
            onBehalfOfUser = if (includeLogin) AuthService.state.value.dataSyncId else null
        )
    )

    private fun playerContext() = InnerTubeContext(
        InnerTubeClientInfo(
            clientName = "ANDROID_VR",
            clientVersion = "1.43.32",
            visitorData = activeVisitorData(),
            osName = "Android",
            osVersion = "12",
            deviceMake = "Oculus",
            deviceModel = "Quest 3"
        )
    )

    private fun tvContext() = InnerTubeContext(
        InnerTubeClientInfo(
            clientName = "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
            clientVersion = "2.0",
            visitorData = activeVisitorData()
        )
    )

    private fun Request.Builder.withAuthHeaders(useAuth: Boolean): Request.Builder {
        if (!useAuth) return this
        AuthService.cookieHeader()?.let { header("Cookie", it) }
        AuthService.authorizationHeader()?.let { header("Authorization", it) }
        return this
    }

    private fun rememberVisitorData(jsonString: String) {
        val extracted = try {
            JSONObject(jsonString)
                .optJSONObject("responseContext")
                ?.optString("visitorData")
                ?.takeIf { it.isNotBlank() }
        } catch (_: Exception) {
            null
        }
        if (extracted != null) {
            visitorData = extracted
        }
    }

    fun hasVisitorData(): Boolean = !visitorData.isNullOrBlank()

    suspend fun ensureVisitorData() {
        if (hasVisitorData()) return
        runCatching { getHomeFeed() }
    }

    suspend fun getHomeFeed(): String = withContext(Dispatchers.IO) {
        val payload = InnerTubeHomeRequest(context = webRemixContext())
        val body = json.encodeToString(payload).toRequestBody(mediaType)
        
        val request = Request.Builder()
            .url("https://music.youtube.com/youtubei/v1/browse?alt=json")
            .post(body)
            .build()
            
        webRemixClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val bodyString = response.body?.string() ?: ""
            rememberVisitorData(bodyString)
            return@withContext bodyString
        }
    }
    
    suspend fun search(query: String, params: String? = null): String = withContext(Dispatchers.IO) {
        val payload = InnerTubeSearchRequest(context = webRemixContext(), query = query, params = params)
        val body = json.encodeToString(payload).toRequestBody(mediaType)
        
        val request = Request.Builder()
            .url("https://music.youtube.com/youtubei/v1/search?alt=json")
            .post(body)
            .build()
            
        webRemixClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val bodyString = response.body?.string() ?: ""
            rememberVisitorData(bodyString)
            return@withContext bodyString
        }
    }
    
    suspend fun getPlayerPayload(videoId: String): String = withContext(Dispatchers.IO) {
        val payload = InnerTubePlayerRequest(context = playerContext(), videoId = videoId)
        val body = json.encodeToString(payload).toRequestBody(mediaType)
        
        val request = Request.Builder()
            .url("https://music.youtube.com/youtubei/v1/player?alt=json&prettyPrint=false")
            .post(body)
            .build()
            
        playerClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val bodyString = response.body?.string() ?: ""
            rememberVisitorData(bodyString)
            return@withContext bodyString
        }
    }
    
    suspend fun getPlayerPayloadTV(videoId: String): String = withContext(Dispatchers.IO) {
        val payload = InnerTubePlayerRequestTV(context = tvContext(), videoId = videoId)
        val body = json.encodeToString(payload).toRequestBody(mediaType)
        
        val request = Request.Builder()
            .url("https://www.youtube.com/youtubei/v1/player?alt=json&prettyPrint=false")
            .post(body)
            .build()
            
        tvClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val bodyString = response.body?.string() ?: ""
            rememberVisitorData(bodyString)
            return@withContext bodyString
        }
    }
    
    suspend fun getBrowse(browseId: String): String = getBrowseInternal(
        browseId = browseId,
        includeLogin = false,
        useAuth = false
    )

    suspend fun getBrowseAuthenticated(browseId: String): String = getBrowseInternal(
        browseId = browseId,
        includeLogin = true,
        useAuth = true
    )

    private suspend fun getBrowseInternal(
        browseId: String,
        includeLogin: Boolean,
        useAuth: Boolean
    ): String = withContext(Dispatchers.IO) {
        @kotlinx.serialization.Serializable
        data class BrowseRequest(
            val context: InnerTubeContext,
            val browseId: String
        )
        val payload = BrowseRequest(context = webRemixContext(includeLogin = includeLogin), browseId = browseId)
        val body = json.encodeToString(payload).toRequestBody(mediaType)
        
        val request = Request.Builder()
            .url("https://music.youtube.com/youtubei/v1/browse?alt=json")
            .post(body)
            .withAuthHeaders(useAuth)
            .build()
            
        webRemixClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val bodyString = response.body?.string() ?: ""
            rememberVisitorData(bodyString)
            return@withContext bodyString
        }
    }

    suspend fun getLikedSongs(): String = getBrowseInternal(
        browseId = "VLLM",
        includeLogin = true,
        useAuth = true
    )

    suspend fun getUserPlaylists(): String = getBrowseInternal(
        browseId = "FEmusic_liked_playlists",
        includeLogin = true,
        useAuth = true
    )

    suspend fun getYTHistory(): String = getBrowseInternal(
        browseId = "FEmusic_history",
        includeLogin = true,
        useAuth = true
    )

    suspend fun getNext(videoId: String, playlistId: String? = null): String = withContext(Dispatchers.IO) {
        @kotlinx.serialization.Serializable
        data class NextRequest(
            val context: InnerTubeContext,
            val videoId: String,
            val playlistId: String? = null
        )

        val payload = NextRequest(
            context = webRemixContext(),
            videoId = videoId,
            playlistId = playlistId
        )
        val body = json.encodeToString(payload).toRequestBody(mediaType)

        val request = Request.Builder()
            .url("https://music.youtube.com/youtubei/v1/next?alt=json&prettyPrint=false")
            .post(body)
            .build()

        webRemixClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val bodyString = response.body?.string() ?: ""
            rememberVisitorData(bodyString)
            return@withContext bodyString
        }
    }

    suspend fun getPlaylistQueue(playlistId: String, authenticated: Boolean = false): String = withContext(Dispatchers.IO) {
        @kotlinx.serialization.Serializable
        data class PlaylistQueueRequest(
            val context: InnerTubeContext,
            val playlistId: String
        )

        val payload = PlaylistQueueRequest(
            context = webRemixContext(includeLogin = authenticated),
            playlistId = playlistId
        )
        val body = json.encodeToString(payload).toRequestBody(mediaType)

        val request = Request.Builder()
            .url("https://music.youtube.com/youtubei/v1/next?alt=json&prettyPrint=false")
            .post(body)
            .withAuthHeaders(authenticated)
            .build()

        webRemixClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val bodyString = response.body?.string() ?: ""
            rememberVisitorData(bodyString)
            return@withContext bodyString
        }
    }
    suspend fun getSearchSuggestions(query: String): String = withContext(Dispatchers.IO) {
        @kotlinx.serialization.Serializable
        data class SuggestionsRequest(
            val context: InnerTubeContext,
            val input: String
        )

        val payload = SuggestionsRequest(context = webRemixContext(), input = query)
        val body = json.encodeToString(payload).toRequestBody(mediaType)

        val request = Request.Builder()
            .url("https://music.youtube.com/youtubei/v1/music/get_search_suggestions?alt=json&prettyPrint=false")
            .post(body)
            .build()

        webRemixClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Unexpected code $response")
            val bodyString = response.body?.string() ?: ""
            rememberVisitorData(bodyString)
            return@withContext bodyString
        }
    }
}
