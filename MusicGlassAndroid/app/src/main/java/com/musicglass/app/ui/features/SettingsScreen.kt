package com.musicglass.app.ui.features

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Login
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.musicglass.app.persistence.AppSettingsRepository
import com.musicglass.app.persistence.AppThemeMode
import com.musicglass.app.persistence.AudioQualityMode
import com.musicglass.app.youtubemusic.AuthService
import java.io.File
import java.text.DecimalFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class SettingsViewModel(application: Application) : AndroidViewModel(application) {
    val settings = AppSettingsRepository.state
    val auth = AuthService.state

    private val _cacheSizeText = MutableStateFlow("Calcul...")
    val cacheSizeText: StateFlow<String> = _cacheSizeText

    init {
        loadCacheSize()
    }

    fun setTheme(theme: AppThemeMode) {
        AppSettingsRepository.setTheme(theme)
    }

    fun setAudioQuality(audioQuality: AudioQualityMode) {
        AppSettingsRepository.setAudioQuality(audioQuality)
    }

    fun setDebugLogsEnabled(enabled: Boolean) {
        AppSettingsRepository.setDebugLogsEnabled(enabled)
    }

    fun logout() {
        AuthService.clear()
    }

    fun loadCacheSize() {
        viewModelScope.launch {
            val size = withContext(Dispatchers.IO) {
                getApplication<Application>().cacheDir.safeSize()
            }
            _cacheSizeText.value = size.toByteSizeText()
        }
    }

    fun clearCache() {
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                getApplication<Application>().cacheDir.deleteChildren()
            }
            loadCacheSize()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = viewModel(),
    onLogin: () -> Unit
) {
    val settings by viewModel.settings.collectAsState()
    val auth by viewModel.auth.collectAsState()
    val cacheSizeText by viewModel.cacheSizeText.collectAsState()

    LaunchedEffect(Unit) {
        viewModel.loadCacheSize()
    }

    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Top),
        topBar = {
            TopAppBar(
                title = { Text("Réglages") },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            item {
                SettingsCard(title = "Compte YouTube Music") {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text("Statut", fontWeight = FontWeight.SemiBold)
                            Text(
                                if (auth.isAuthenticated) "Connecté" else "Non connecté",
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        if (auth.isAuthenticated) {
                            OutlinedButton(onClick = viewModel::logout) {
                                Icon(Icons.Filled.Logout, contentDescription = null)
                                Spacer(Modifier.width(6.dp))
                                Text("Se déconnecter")
                            }
                        } else {
                            Button(onClick = onLogin) {
                                Icon(Icons.Filled.Login, contentDescription = null)
                                Spacer(Modifier.width(6.dp))
                                Text("Se connecter")
                            }
                        }
                    }
                }
            }

            item {
                SettingsCard(title = "Apparence") {
                    Text("Thème", fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(8.dp))
                    ChipRow {
                        ThemeChip("Système", AppThemeMode.SYSTEM, settings.theme, viewModel::setTheme)
                        ThemeChip("Clair", AppThemeMode.LIGHT, settings.theme, viewModel::setTheme)
                        ThemeChip("Sombre", AppThemeMode.DARK, settings.theme, viewModel::setTheme)
                    }

                    Spacer(Modifier.height(18.dp))

                    Text("Qualité audio", fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(8.dp))
                    ChipRow {
                        AudioQualityChip("Auto", AudioQualityMode.AUTO, settings.audioQuality, viewModel::setAudioQuality)
                        AudioQualityChip("Élevée", AudioQualityMode.HIGH, settings.audioQuality, viewModel::setAudioQuality)
                        AudioQualityChip("Économie", AudioQualityMode.DATA_SAVER, settings.audioQuality, viewModel::setAudioQuality)
                    }
                }
            }

            item {
                SettingsCard(title = "Cache") {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text("Taille du cache", fontWeight = FontWeight.SemiBold)
                            Text(cacheSizeText, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        TextButton(onClick = viewModel::clearCache) {
                            Icon(Icons.Filled.Delete, contentDescription = null)
                            Spacer(Modifier.width(6.dp))
                            Text("Vider")
                        }
                    }
                }
            }

            item {
                SettingsCard(title = "Débogage") {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text("Journaux de débogage", fontWeight = FontWeight.SemiBold)
                            Text(
                                "Active les traces locales utiles pour diagnostiquer YouTube Music.",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                        Switch(
                            checked = settings.debugLogsEnabled,
                            onCheckedChange = viewModel::setDebugLogsEnabled
                        )
                    }
                }
            }

            item {
                SettingsCard(title = "À propos") {
                    Text("Version", fontWeight = FontWeight.SemiBold)
                    Text("1.0 MVP", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "MusicGlass est un prototype de client musical tiers. Il n’est pas affilié à YouTube, Google, Apple ni à leurs filiales. Aucun identifiant ni secret d’API n’est intégré dans l’app.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        }
    }
}

@Composable
private fun SettingsCard(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(4.dp))
            content()
        }
    }
}

@Composable
private fun ChipRow(content: @Composable RowScope.() -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), content = content)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ThemeChip(
    label: String,
    value: AppThemeMode,
    selected: AppThemeMode,
    onSelect: (AppThemeMode) -> Unit
) {
    FilterChip(
        selected = selected == value,
        onClick = { onSelect(value) },
        label = { Text(label) }
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AudioQualityChip(
    label: String,
    value: AudioQualityMode,
    selected: AudioQualityMode,
    onSelect: (AudioQualityMode) -> Unit
) {
    FilterChip(
        selected = selected == value,
        onClick = { onSelect(value) },
        label = { Text(label) }
    )
}

private fun File.safeSize(): Long {
    if (!exists()) return 0L
    if (isFile) return length()
    return listFiles()?.sumOf { it.safeSize() } ?: 0L
}

private fun File.deleteChildren() {
    listFiles()?.forEach { it.deleteRecursively() }
}

private fun Long.toByteSizeText(): String {
    if (this <= 0L) return "0 o"
    val units = arrayOf("o", "Ko", "Mo", "Go")
    var value = toDouble()
    var unit = 0
    while (value >= 1024 && unit < units.lastIndex) {
        value /= 1024
        unit += 1
    }
    return "${DecimalFormat("#,##0.#").format(value)} ${units[unit]}"
}
