package com.musicglass.app

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.content.pm.PackageManager
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import com.musicglass.app.core.update.UpdateRepository
import com.musicglass.app.persistence.AppSettingsRepository
import com.musicglass.app.persistence.AppThemeMode
import com.musicglass.app.persistence.PlaybackHistoryRepository
import com.musicglass.app.ui.MainScreen
import com.musicglass.app.ui.theme.MusicGlassTheme
import com.musicglass.app.youtubemusic.AuthService

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AuthService.init(applicationContext)
        AppSettingsRepository.init(applicationContext)
        PlaybackHistoryRepository.init(applicationContext)
        UpdateRepository.init(applicationContext)
        requestNotificationPermissionIfNeeded()
        enableEdgeToEdge()
        setContent {
            val settings by AppSettingsRepository.state.collectAsState()
            val systemDark = isSystemInDarkTheme()
            val darkTheme = when (settings.theme) {
                AppThemeMode.SYSTEM -> systemDark
                AppThemeMode.LIGHT -> false
                AppThemeMode.DARK -> true
            }

            MusicGlassTheme(darkTheme = darkTheme) {
                // A surface container using the 'background' color from the theme
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    MainScreen()
                }
            }
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2002)
    }
}
