package com.musicglass.app.persistence

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

enum class AppThemeMode(val storageValue: String) {
    SYSTEM("System"),
    LIGHT("Light"),
    DARK("Dark");

    companion object {
        fun fromStorage(value: String?): AppThemeMode {
            return entries.firstOrNull { it.storageValue == value } ?: SYSTEM
        }
    }
}

enum class AudioQualityMode(val storageValue: String) {
    AUTO("Auto"),
    HIGH("High"),
    DATA_SAVER("Data Saver");

    companion object {
        fun fromStorage(value: String?): AudioQualityMode {
            return entries.firstOrNull { it.storageValue == value } ?: AUTO
        }
    }
}

data class AppSettingsState(
    val theme: AppThemeMode = AppThemeMode.SYSTEM,
    val audioQuality: AudioQualityMode = AudioQualityMode.AUTO,
    val debugLogsEnabled: Boolean = false
)

object AppSettingsRepository {
    private const val PREFS = "musicglass_settings"
    private const val KEY_THEME = "appTheme"
    private const val KEY_AUDIO_QUALITY = "audioQuality"
    private const val KEY_DEBUG_LOGS = "debugLogsEnabled"

    private var appContext: Context? = null

    private val _state = MutableStateFlow(AppSettingsState())
    val state: StateFlow<AppSettingsState> = _state

    fun init(context: Context) {
        appContext = context.applicationContext
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        _state.value = AppSettingsState(
            theme = AppThemeMode.fromStorage(prefs.getString(KEY_THEME, null)),
            audioQuality = AudioQualityMode.fromStorage(prefs.getString(KEY_AUDIO_QUALITY, null)),
            debugLogsEnabled = prefs.getBoolean(KEY_DEBUG_LOGS, false)
        )
    }

    fun setTheme(theme: AppThemeMode) {
        update(_state.value.copy(theme = theme)) {
            putString(KEY_THEME, theme.storageValue)
        }
    }

    fun setAudioQuality(audioQuality: AudioQualityMode) {
        update(_state.value.copy(audioQuality = audioQuality)) {
            putString(KEY_AUDIO_QUALITY, audioQuality.storageValue)
        }
    }

    fun setDebugLogsEnabled(enabled: Boolean) {
        update(_state.value.copy(debugLogsEnabled = enabled)) {
            putBoolean(KEY_DEBUG_LOGS, enabled)
        }
    }

    private fun update(
        newState: AppSettingsState,
        edit: android.content.SharedPreferences.Editor.() -> Unit
    ) {
        _state.value = newState
        appContext
            ?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            ?.edit()
            ?.apply {
                edit()
                apply()
            }
    }
}
