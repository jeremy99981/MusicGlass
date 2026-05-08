package com.musicglass.app.ui.features.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import com.musicglass.app.BuildConfig
import com.musicglass.app.core.update.UpdateCheckState
import com.musicglass.app.core.update.UpdateViewModel
import com.musicglass.app.persistence.AppThemeMode
import com.musicglass.app.persistence.AudioQualityMode
import com.musicglass.app.ui.features.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileBottomSheet(
    onDismiss: () -> Unit,
    settingsViewModel: SettingsViewModel,
    updateViewModel: UpdateViewModel,
    onLoginYouTubeMusic: () -> Unit,
    onLoginAccount: () -> Unit
) {
    val authState by settingsViewModel.auth.collectAsState()
    val settingsState by settingsViewModel.settings.collectAsState()
    val cacheSizeText by settingsViewModel.cacheSizeText.collectAsState()
    val updateState by updateViewModel.updateState.collectAsState()
    
    var showClearCacheDialog by remember { mutableStateOf(false) }
    var showLogoutDialog by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false),
        containerColor = MaterialTheme.colorScheme.surface,
        dragHandle = { BottomSheetDefaults.DragHandle() }
    ) {
        val configuration = LocalConfiguration.current
        val screenHeight = configuration.screenHeightDp.dp

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = screenHeight * 0.92f)
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
        ) {
            ProfileHeader(onDismiss = onDismiss)
            
            ProfileIdentityCard()
            
            Spacer(modifier = Modifier.height(24.dp))
            
            ProfileSection(title = "Compte") {
                ProfileListItem(
                    title = "Connecter un compte",
                    subtitle = "Compte MusicGlass, profil et préférences",
                    icon = Icons.Default.AccountCircle,
                    onClick = onLoginAccount
                )
                ProfileListItem(
                    title = "Préférences du compte",
                    icon = Icons.Default.ManageAccounts,
                    enabled = false,
                    onClick = { }
                )
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            ProfileSection(title = "YouTube Music") {
                YouTubeMusicStatusCard(
                    isConnected = authState.isAuthenticated,
                    onConnect = onLoginYouTubeMusic,
                    onDisconnect = { showLogoutDialog = true }
                )
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            ProfileSection(title = "Application") {
                ProfileListItem(
                    title = "Qualité audio",
                    subtitle = when(settingsState.audioQuality) {
                        AudioQualityMode.AUTO -> "Auto"
                        AudioQualityMode.HIGH -> "Élevée (256kbps)"
                        AudioQualityMode.DATA_SAVER -> "Économie"
                    },
                    icon = Icons.Default.MusicNote,
                    onClick = { /* Could open a dialog or navigate */ }
                )
                ProfileListItem(
                    title = "Lecture et confort",
                    icon = Icons.Default.PlayCircle,
                    onClick = { }
                )
                ProfileListItem(
                    title = "Notifications",
                    icon = Icons.Default.Notifications,
                    onClick = { }
                )
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            ProfileSection(title = "Données") {
                ProfileListItem(
                    title = "Historique d'écoute",
                    icon = Icons.Default.History,
                    trailingIcon = Icons.Default.ChevronRight,
                    onClick = { }
                )
                ProfileListItem(
                    title = "Confidentialité",
                    icon = Icons.Default.PrivacyTip,
                    onClick = { }
                )
                ProfileListItem(
                    title = "Vider le cache",
                    subtitle = cacheSizeText,
                    icon = Icons.Default.DeleteOutline,
                    onClick = { showClearCacheDialog = true }
                )
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            ProfileSection(title = "À propos") {
                ProfileListItem(
                    title = "Version de l'app",
                    subtitle = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                    icon = Icons.Default.Info,
                    onClick = { }
                )
                UpdateStatusItem(
                    state = updateState,
                    onCheckUpdates = { updateViewModel.checkForUpdateFromSettings() },
                    onDownload = { 
                        if (updateState is UpdateCheckState.UpdateAvailable) {
                            updateViewModel.showUpdateDialog()
                        }
                    }
                )
            }
            
            Spacer(modifier = Modifier.height(32.dp))
        }
    }

    if (showClearCacheDialog) {
        AlertDialog(
            onDismissRequest = { showClearCacheDialog = false },
            title = { Text("Vider le cache ?") },
            text = { Text("Les données temporaires seront supprimées. Vos playlists et préférences ne seront pas supprimées.") },
            confirmButton = {
                TextButton(onClick = {
                    settingsViewModel.clearCache()
                    showClearCacheDialog = false
                }) {
                    Text("Vider", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearCacheDialog = false }) {
                    Text("Annuler")
                }
            }
        )
    }

    if (showLogoutDialog) {
        AlertDialog(
            onDismissRequest = { showLogoutDialog = false },
            title = { Text("Déconnecter YouTube Music ?") },
            text = { Text("La session YouTube Music sera supprimée de cet appareil.") },
            confirmButton = {
                TextButton(onClick = {
                    settingsViewModel.logout()
                    showLogoutDialog = false
                }) {
                    Text("Déconnecter", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showLogoutDialog = false }) {
                    Text("Annuler")
                }
            }
        )
    }
}

@Composable
private fun ProfileHeader(onDismiss: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 16.dp)
    ) {
        Text(
            text = "Profil",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.align(Alignment.Center)
        )
        IconButton(
            onClick = onDismiss,
            modifier = Modifier.align(Alignment.CenterEnd)
        ) {
            Icon(Icons.Default.Close, contentDescription = "Fermer")
        }
    }
}

@Composable
private fun ProfileIdentityCard() {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.elevatedCardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .background(
                        brush = androidx.compose.ui.graphics.Brush.linearGradient(
                            colors = listOf(Color(0xFFC26E7A), Color(0xFF8E44AD))
                        ),
                        shape = CircleShape
                    ),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "MG",
                    color = Color.White,
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold
                )
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            Text(
                text = "Invité",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "Compte local non connecté",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ProfileSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            text = title.uppercase(),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 8.dp, bottom = 8.dp)
        )
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = MaterialTheme.shapes.large,
            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
            tonalElevation = 1.dp
        ) {
            Column {
                content()
            }
        }
    }
}

@Composable
private fun ProfileListItem(
    title: String,
    subtitle: String? = null,
    icon: ImageVector,
    trailingIcon: ImageVector? = null,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    ListItem(
        headlineContent = { 
            Text(
                text = title,
                fontWeight = FontWeight.Medium,
                color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
            ) 
        },
        supportingContent = subtitle?.let { 
            { 
                Text(
                    text = it,
                    color = if (enabled) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f)
                ) 
            } 
        },
        leadingContent = {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.primary.copy(alpha = 0.38f)
            )
        },
        trailingContent = trailingIcon?.let {
            { Icon(it, contentDescription = null, tint = MaterialTheme.colorScheme.outline) }
        },
        modifier = Modifier.clickable(enabled = enabled, onClick = onClick),
        colors = ListItemDefaults.colors(containerColor = Color.Transparent)
    )
}

@Composable
private fun YouTubeMusicStatusCard(
    isConnected: Boolean,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit
) {
    ListItem(
        headlineContent = { 
            Text(
                text = if (isConnected) "YouTube Music connecté" else "Connecter YouTube Music",
                fontWeight = FontWeight.Bold
            ) 
        },
        supportingContent = { 
            Text(text = if (isConnected) "Session active" else "Synchroniser playlists et favoris") 
        },
        leadingContent = {
            Icon(
                imageVector = Icons.Default.MusicNote,
                contentDescription = null,
                tint = if (isConnected) Color(0xFFF44336) else MaterialTheme.colorScheme.primary
            )
        },
        trailingContent = {
            if (isConnected) {
                TextButton(onClick = onDisconnect) {
                    Text("Déconnecter", color = MaterialTheme.colorScheme.error)
                }
            } else {
                Button(onClick = onConnect) {
                    Text("Connecter")
                }
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent)
    )
}

@Composable
private fun UpdateStatusItem(
    state: UpdateCheckState,
    onCheckUpdates: () -> Unit,
    onDownload: () -> Unit
) {
    ListItem(
        headlineContent = { Text("Mise à jour de l'application") },
        supportingContent = {
            Text(
                text = when (state) {
                    is UpdateCheckState.Checking -> "Recherche..."
                    is UpdateCheckState.NoUpdate -> "À jour"
                    is UpdateCheckState.UpdateAvailable -> "Version ${state.info.latestVersion} disponible"
                    is UpdateCheckState.Error -> "Impossible de vérifier"
                    else -> "Vérifier les mises à jour"
                }
            )
        },
        leadingContent = {
            Icon(
                imageVector = Icons.Default.SystemUpdate,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
        },
        trailingContent = {
            when (state) {
                is UpdateCheckState.Checking -> CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                is UpdateCheckState.UpdateAvailable -> {
                    Button(onClick = onDownload) {
                        Text("Télécharger")
                    }
                }
                else -> {
                    IconButton(onClick = onCheckUpdates) {
                        Icon(Icons.Default.Refresh, contentDescription = "Recharger")
                    }
                }
            }
        },
        modifier = Modifier.clickable { onCheckUpdates() },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent)
    )
}
