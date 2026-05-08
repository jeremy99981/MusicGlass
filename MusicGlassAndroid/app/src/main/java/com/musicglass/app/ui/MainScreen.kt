package com.musicglass.app.ui

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import coil.compose.AsyncImage
import com.musicglass.app.BuildConfig
import com.musicglass.app.core.update.ChangelogDialog
import com.musicglass.app.core.update.UpdateAvailableDialog
import com.musicglass.app.core.update.UpdateCheckState
import com.musicglass.app.core.update.UpdateViewModel
import com.musicglass.app.ui.features.AlbumScreen
import com.musicglass.app.ui.features.ArtistScreen
import com.musicglass.app.ui.features.HomeScreen
import com.musicglass.app.ui.features.LibraryScreen
import com.musicglass.app.ui.features.LoginWebViewScreen
import com.musicglass.app.ui.features.SearchScreen
import com.musicglass.app.ui.features.SettingsScreen
import com.musicglass.app.youtubemusic.InnerTubeClient
import com.musicglass.app.youtubemusic.InnerTubeJSONMapper
import com.musicglass.app.youtubemusic.ItemType
import com.musicglass.app.ui.player.FullPlayerDialog
import com.musicglass.app.youtubemusic.bestThumbnailUrl
import kotlinx.coroutines.launch

import com.musicglass.app.ui.features.SettingsScreen
import com.musicglass.app.ui.features.SettingsViewModel
import com.musicglass.app.ui.features.profile.ProfileBottomSheet

import com.musicglass.app.ui.features.library.artists.ArtistsScreen
import com.musicglass.app.ui.features.auth.AccountAuthScreen

sealed class Screen(val route: String, val title: String, val icon: androidx.compose.ui.graphics.vector.ImageVector) {
    object Home : Screen("home", "Accueil", Icons.Filled.Home)
    object Search : Screen("search", "Recherche", Icons.Filled.Search)
    object Library : Screen("library", "Bibliothèque", Icons.Filled.LibraryMusic)
    object Settings : Screen("settings", "Réglages", Icons.Filled.Settings)
    object AccountAuth : Screen("account_auth", "Compte MusicGlass", Icons.Filled.AccountCircle)
}

val bottomNavItems = listOf(
    Screen.Home,
    Screen.Search,
    Screen.Library,
    Screen.Settings
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen() {
    val navController = rememberNavController()
    val playerViewModel: com.musicglass.app.playback.PlayerViewModel = viewModel()
    val updateViewModel: UpdateViewModel = viewModel()
    val settingsViewModel: SettingsViewModel = viewModel()
    
    val currentTrack by playerViewModel.currentTrack.collectAsState()
    val currentSongInfo by playerViewModel.currentSongInfo.collectAsState()
    val isLoading by playerViewModel.isLoading.collectAsState()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    val showBottomBar = currentDestination?.route != "login"
    var showFullPlayer by rememberSaveable { mutableStateOf(false) }
    var showProfileSheet by rememberSaveable { mutableStateOf(false) }
    
    val scope = rememberCoroutineScope()
    val innerTubeClient = remember { InnerTubeClient() }
    val mapper = remember { InnerTubeJSONMapper() }

    // Update system state
    val updateState by updateViewModel.updateState.collectAsState()
    val showUpdateDialog by updateViewModel.showUpdateDialog.collectAsState()
    val showChangelogDialog by updateViewModel.showChangelogDialog.collectAsState()
    val downloadProgress by updateViewModel.downloadProgress.collectAsState()
    val changelogNotes by updateViewModel.changelogNotes.collectAsState()

    // Check for updates on app startup (only once)
    LaunchedEffect(Unit) {
        updateViewModel.onAppStart()
    }

    fun navigateToMedia(item: com.musicglass.app.youtubemusic.SongItem) {
        val targetId = item.browseId ?: item.id
        val route = when (item.type) {
            ItemType.ALBUM -> "album"
            ItemType.ARTIST -> "artist"
            ItemType.PLAYLIST -> "playlist"
            ItemType.SONG -> "playlist"
        }
        navController.navigate("$route/${Uri.encode(targetId)}")
    }

    LaunchedEffect(currentTrack, currentSongInfo, isLoading) {
        if (currentTrack == null && currentSongInfo == null && !isLoading) {
            showFullPlayer = false
        }
    }
    
    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            contentWindowInsets = WindowInsets(0, 0, 0, 0),
            bottomBar = {
                if (showBottomBar) {
                    Column {
                        MiniPlayer(
                            viewModel = playerViewModel,
                            onExpand = { showFullPlayer = true }
                        )
                        NavigationBar(
                            containerColor = MaterialTheme.colorScheme.surface,
                            contentColor = MaterialTheme.colorScheme.onSurface,
                            windowInsets = NavigationBarDefaults.windowInsets
                        ) {
                            bottomNavItems.forEach { screen ->
                                NavigationBarItem(
                                    icon = { Icon(screen.icon, contentDescription = screen.title) },
                                    label = { Text(screen.title) },
                                    selected = currentDestination?.hierarchy?.any { it.route == screen.route } == true,
                                    onClick = {
                                        navController.navigate(screen.route) {
                                            popUpTo(Screen.Home.route) {
                                                saveState = true
                                            }
                                            launchSingleTop = true
                                            restoreState = true
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
        ) { paddingValues ->
            NavHost(
                navController = navController,
                startDestination = Screen.Home.route,
                modifier = Modifier.padding(paddingValues)
            ) {
                composable(Screen.Home.route) {
                    HomeScreen(
                        onSongClick = { item ->
                            if (item.type == com.musicglass.app.youtubemusic.ItemType.SONG) {
                                playerViewModel.playSongItem(item)
                            } else {
                                navigateToMedia(item)
                            }
                        },
                        onRadio = { item ->
                            if (item.type == com.musicglass.app.youtubemusic.ItemType.SONG) {
                                playerViewModel.playRadio(item)
                            }
                        },
                        onProfileClick = { showProfileSheet = true }
                    )
                }
                composable("playlist/{id}") { backStackEntry ->
                    val id = backStackEntry.arguments?.getString("id") ?: ""
                    com.musicglass.app.ui.features.PlaylistScreen(
                        browseId = id,
                        onBack = { navController.popBackStack() },
                        onSongClick = { item, queue ->
                            if (item.type == com.musicglass.app.youtubemusic.ItemType.SONG) {
                                playerViewModel.playSongItem(item, queue)
                            } else {
                                navigateToMedia(item)
                            }
                        },
                        onRadio = { item -> playerViewModel.playRadio(item) }
                    )
                }
                composable("album/{id}") { backStackEntry ->
                    val id = backStackEntry.arguments?.getString("id") ?: ""
                    AlbumScreen(
                        browseId = id,
                        onBack = { navController.popBackStack() },
                        onSongClick = { item, queue -> playerViewModel.playSongItem(item, queue) },
                        onRadio = { item -> playerViewModel.playRadio(item) }
                    )
                }
                composable("artist/{id}") { backStackEntry ->
                    val id = backStackEntry.arguments?.getString("id") ?: ""
                    ArtistScreen(
                        browseId = id,
                        onBack = { navController.popBackStack() },
                        onSongClick = { item, queue -> playerViewModel.playSongItem(item, queue) },
                        onRadio = { item -> playerViewModel.playRadio(item) },
                        onNavigate = { item -> navigateToMedia(item) }
                    )
                }
                composable(Screen.Search.route) {
                    SearchScreen(
                        onSongClick = { item, queue ->
                            playerViewModel.playSongItem(item, queue)
                        },
                        onRadio = { item -> playerViewModel.playRadio(item) },
                        onNavigate = { item ->
                            navigateToMedia(item)
                        }
                    )
                }
                composable(Screen.Library.route) {
                    LibraryScreen(
                        onLogin = { navController.navigate("login") },
                        onSongClick = { item, queue ->
                            playerViewModel.playSongItem(item, queue)
                        },
                        onRadio = { item -> playerViewModel.playRadio(item) },
                        onNavigate = { item ->
                            navigateToMedia(item)
                        },
                        onArtistsClick = { navController.navigate("library/artists") }
                    )
                }
                composable("library/artists") {
                    ArtistsScreen(
                        onBack = { navController.popBackStack() },
                        onArtistClick = { name, browseId ->
                            if (!browseId.isNullOrBlank()) {
                                navController.navigate("artist/${Uri.encode(browseId)}")
                            } else {
                                // Try to find artist by name via search if browseId is missing
                                scope.launch {
                                    val resolvedId = runCatching {
                                        mapper.mapSearchResults(innerTubeClient.search(name, params = "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"))
                                            .firstOrNull { it.type == ItemType.ARTIST }
                                            ?.browseId
                                    }.getOrNull()
                                    
                                    if (!resolvedId.isNullOrBlank()) {
                                        navController.navigate("artist/${Uri.encode(resolvedId)}")
                                    }
                                }
                            }
                        }
                    )
                }
                composable(Screen.Settings.route) {
                    SettingsScreen(
                        onLogin = { navController.navigate("login") },
                        updateViewModel = updateViewModel
                    )
                }
                composable("login") {
                    LoginWebViewScreen(
                        onLoginSuccess = {
                            navController.popBackStack()
                        }
                    )
                }
                composable(Screen.AccountAuth.route) {
                    AccountAuthScreen(
                        onBack = { navController.popBackStack() },
                        onSuccess = { navController.popBackStack() }
                    )
                }
            }
        }

        if (showProfileSheet) {
            ProfileBottomSheet(
                onDismiss = { showProfileSheet = false },
                settingsViewModel = settingsViewModel,
                updateViewModel = updateViewModel,
                onLoginYouTubeMusic = {
                    showProfileSheet = false
                    navController.navigate("login")
                },
                onLoginAccount = {
                    showProfileSheet = false
                    navController.navigate(Screen.AccountAuth.route)
                }
            )
        }

        if (showFullPlayer) {
            FullPlayerDialog(
                viewModel = playerViewModel,
                onDismiss = { showFullPlayer = false },
                onArtistClick = { artistName, browseId ->
                    showFullPlayer = false
                    if (!browseId.isNullOrBlank()) {
                        navController.navigate("artist/${Uri.encode(browseId)}")
                    } else {
                        scope.launch {
                            val resolvedBrowseId = runCatching {
                                mapper.mapSearchResults(
                                    innerTubeClient.search(
                                        artistName,
                                        params = "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
                                    )
                                )
                                    .firstOrNull {
                                        it.type == ItemType.ARTIST &&
                                            it.title.equals(artistName, ignoreCase = true) &&
                                            !it.browseId.isNullOrBlank()
                                    }
                                    ?.browseId
                                    ?: mapper.mapSearchResults(
                                        innerTubeClient.search(
                                            artistName,
                                            params = "EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D"
                                        )
                                    )
                                        .firstOrNull { it.type == ItemType.ARTIST && !it.browseId.isNullOrBlank() }
                                        ?.browseId
                            }.getOrNull()

                            if (!resolvedBrowseId.isNullOrBlank()) {
                                navController.navigate("artist/${Uri.encode(resolvedBrowseId)}")
                            }
                        }
                    }
                }
            )
        }

        // Update available dialog
        if (showUpdateDialog && updateState is UpdateCheckState.UpdateAvailable) {
            val info = (updateState as UpdateCheckState.UpdateAvailable).info
            UpdateAvailableDialog(
                updateInfo = info,
                downloadState = updateState,
                downloadProgress = downloadProgress,
                onDownload = { updateViewModel.downloadUpdate(info) },
                onDismiss = { updateViewModel.dismissUpdateDialog() }
            )
        }

        // Also show dialog during download (state transitions away from UpdateAvailable)
        if (showUpdateDialog && (updateState is UpdateCheckState.Downloading || updateState is UpdateCheckState.Error)) {
            val cachedInfo = com.musicglass.app.core.update.UpdateRepository.getCachedUpdateInfo()
            if (cachedInfo != null) {
                UpdateAvailableDialog(
                    updateInfo = cachedInfo,
                    downloadState = updateState,
                    downloadProgress = downloadProgress,
                    onDownload = { updateViewModel.downloadUpdate(cachedInfo) },
                    onDismiss = { updateViewModel.dismissUpdateDialog() }
                )
            }
        }

        // Changelog dialog (shown once after update)
        if (showChangelogDialog) {
            ChangelogDialog(
                versionName = BuildConfig.VERSION_NAME,
                releaseNotes = changelogNotes,
                onDismiss = { updateViewModel.dismissChangelogDialog() }
            )
        }
    }
}

@Composable
fun MiniPlayer(
    viewModel: com.musicglass.app.playback.PlayerViewModel,
    onExpand: () -> Unit
) {
    val currentTrack by viewModel.currentTrack.collectAsState()
    val currentSongInfo by viewModel.currentSongInfo.collectAsState()
    val isPlaying by viewModel.isPlaying.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val error by viewModel.error.collectAsState()
    val recoveryStatus by viewModel.recoveryStatus.collectAsState()

    // If we have neither track nor fallback info, don't show the player
    if (currentTrack == null && currentSongInfo == null && !isLoading) return

    fun resolvedTitle(): String {
        val fallbackTitle = currentSongInfo?.title?.trim().orEmpty()
        val currentTitle = currentTrack?.title?.trim().orEmpty()
        return when {
            fallbackTitle.isNotEmpty() -> fallbackTitle
            currentTitle.isNotEmpty() && !currentTitle.equals("Titre inconnu", ignoreCase = true) -> currentTitle
            currentTitle.isNotEmpty() -> currentTitle
            else -> "Chargement..."
        }
    }

    fun resolvedSubtitle(): String {
        if (recoveryStatus != null) return recoveryStatus!!
        if (error != null) return error!!

        val fallbackArtist = currentSongInfo?.artists
            ?.joinToString(", ") { it.name.trim() }
            ?.takeIf { it.isNotBlank() }
        val currentAuthor = currentTrack?.author?.trim().orEmpty()

        return when {
            !fallbackArtist.isNullOrEmpty() -> fallbackArtist
            currentAuthor.isNotEmpty() -> currentAuthor
            else -> ""
        }
    }

    fun resolvedArtworkUrl(): String? {
        val albumArtwork = currentSongInfo?.album?.thumbnails?.bestThumbnailUrl()
        if (albumArtwork != null) return albumArtwork

        val songArtwork = currentSongInfo?.thumbnails?.bestThumbnailUrl()
        if (songArtwork != null) return songArtwork

        return currentTrack?.thumbnails?.bestThumbnailUrl()
    }

    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        tonalElevation = 3.dp,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onExpand)
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            val imageUrl = resolvedArtworkUrl()
            if (imageUrl != null) {
                AsyncImage(
                    model = imageUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(48.dp)
                        .clip(RoundedCornerShape(8.dp))
                )
            } else {
                Box(modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.primaryContainer))
            }
            
            Spacer(modifier = Modifier.width(12.dp))
            
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = resolvedTitle(),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = resolvedSubtitle(),
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (error != null && recoveryStatus == null) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    strokeWidth = 2.dp
                )
            } else {
                IconButton(onClick = { viewModel.togglePlayPause() }) {
                    Icon(
                        imageVector = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        contentDescription = if (isPlaying) "Pause" else "Play"
                    )
                }
            }
        }
    }
}

@Composable
fun PlaceholderScreen(title: String) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top)),
        contentAlignment = Alignment.Center
    ) {
        Text(text = title, style = MaterialTheme.typography.headlineMedium)
    }
}
