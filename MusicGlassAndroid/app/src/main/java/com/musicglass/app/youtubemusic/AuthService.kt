package com.musicglass.app.youtubemusic

import android.content.Context
import android.webkit.CookieManager
import java.security.MessageDigest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class AuthState(
    val cookieHeader: String? = null,
    val dataSyncId: String? = null,
    val visitorData: String? = null
) {
    val isAuthenticated: Boolean
        get() = !sapisid.isNullOrBlank() && !dataSyncId.isNullOrBlank()

    val sapisid: String?
        get() = cookieHeader
            ?.split(";")
            ?.map { it.trim() }
            ?.firstOrNull { it.startsWith("SAPISID=") || it.startsWith("__Secure-3PAPISID=") }
            ?.substringAfter("=")
            ?.takeIf { it.isNotBlank() }
}

object AuthService {
    private const val PREFS = "musicglass_auth"
    private const val KEY_COOKIE_HEADER = "cookie_header"
    private const val KEY_DATA_SYNC_ID = "data_sync_id"
    private const val KEY_VISITOR_DATA = "visitor_data"
    private const val ORIGIN = "https://music.youtube.com"

    private var appContext: Context? = null

    private val _state = MutableStateFlow(AuthState())
    val state: StateFlow<AuthState> = _state

    fun init(context: Context) {
        appContext = context.applicationContext
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        _state.value = AuthState(
            cookieHeader = prefs.getString(KEY_COOKIE_HEADER, null),
            dataSyncId = prefs.getString(KEY_DATA_SYNC_ID, null)?.normalizedDataSyncId(),
            visitorData = prefs.getString(KEY_VISITOR_DATA, null)
        )
    }

    fun save(cookieHeader: String?, dataSyncId: String?, visitorData: String?) {
        val normalizedDataSyncId = dataSyncId.normalizedDataSyncId()
        val state = AuthState(
            cookieHeader = cookieHeader?.takeIf { it.isNotBlank() },
            dataSyncId = normalizedDataSyncId,
            visitorData = visitorData?.takeIf { it.isNotBlank() }
        )
        _state.value = state

        appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            ?.edit()
            ?.putString(KEY_COOKIE_HEADER, state.cookieHeader)
            ?.putString(KEY_DATA_SYNC_ID, state.dataSyncId)
            ?.putString(KEY_VISITOR_DATA, state.visitorData)
            ?.apply()
    }

    fun clear() {
        _state.value = AuthState()
        appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            ?.edit()
            ?.clear()
            ?.apply()
        CookieManager.getInstance().removeAllCookies(null)
        CookieManager.getInstance().flush()
    }

    fun cookieHeader(): String? = _state.value.cookieHeader

    fun authorizationHeader(): String? {
        val sapisid = _state.value.sapisid ?: return null
        val timestamp = System.currentTimeMillis() / 1000L
        val payload = "$timestamp $sapisid $ORIGIN"
        val hash = MessageDigest.getInstance("SHA-1")
            .digest(payload.toByteArray())
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        return "SAPISIDHASH ${timestamp}_$hash"
    }

    private fun String?.normalizedDataSyncId(): String? {
        val trimmed = this?.trim().orEmpty()
        val normalized = trimmed.substringBefore("||").trim()
        return normalized.takeIf { it.isNotBlank() }
    }
}
