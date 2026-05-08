package com.musicglass.app.core.update

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.FileProvider
import com.musicglass.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

/**
 * Singleton repository for checking GitHub Releases and managing
 * the download of updated APKs.
 */
object UpdateRepository {
    private const val TAG = "UpdateRepository"
    private const val PREFS = "musicglass_update"
    private const val KEY_LAST_SEEN_VERSION = "lastSeenVersion"
    private const val KEY_DISMISSED_VERSION = "dismissedVersion"

    private var appContext: Context? = null

    private val json = Json { ignoreUnknownKeys = true }

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    private val _updateState = MutableStateFlow<UpdateCheckState>(UpdateCheckState.Idle)
    val updateState: StateFlow<UpdateCheckState> = _updateState

    private val _downloadProgress = MutableStateFlow(0f)
    val downloadProgress: StateFlow<Float> = _downloadProgress

    private var cachedUpdateInfo: UpdateInfo? = null

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    /**
     * Returns the last version the user has opened.
     * Used to determine if the changelog should be shown.
     */
    fun getLastSeenVersion(): String? {
        val prefs = appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return prefs?.getString(KEY_LAST_SEEN_VERSION, null)
    }

    /**
     * Marks the current version as "seen" so the changelog is only shown once.
     */
    fun markCurrentVersionSeen() {
        val prefs = appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs?.edit()?.putString(KEY_LAST_SEEN_VERSION, BuildConfig.VERSION_NAME)?.apply()
    }

    /**
     * Returns the version the user dismissed (don't show again).
     */
    fun getDismissedVersion(): String? {
        val prefs = appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return prefs?.getString(KEY_DISMISSED_VERSION, null)
    }

    /**
     * Marks a version as dismissed so we don't prompt for it again at startup.
     */
    fun dismissVersion(version: String) {
        val prefs = appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs?.edit()?.putString(KEY_DISMISSED_VERSION, version)?.apply()
    }

    /**
     * Checks the latest GitHub release for the configured repository.
     * Updates the [updateState] flow with the result.
     */
    suspend fun checkForUpdate(forceShow: Boolean = false): UpdateInfo? = withContext(Dispatchers.IO) {
        try {
            _updateState.value = UpdateCheckState.Checking

            val repo = BuildConfig.GITHUB_REPO
            val url = "https://api.github.com/repos/$repo/releases/latest"

            val request = Request.Builder()
                .url(url)
                .header("Accept", "application/vnd.github+json")
                .get()
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                if (response.code == 404) {
                    // 404 means no releases found for this repository yet
                    _updateState.value = UpdateCheckState.NoUpdate
                    return@withContext null
                }
                Log.w(TAG, "GitHub API returned ${response.code}")
                _updateState.value = UpdateCheckState.Error("Erreur serveur (${response.code})")
                return@withContext null
            }

            val body = response.body?.string() ?: run {
                _updateState.value = UpdateCheckState.Error("Réponse vide")
                return@withContext null
            }

            val release = json.decodeFromString<GitHubRelease>(body)
            Log.d(TAG, "Latest release found: ${release.tagName} (Name: ${release.name})")

            // Find the best .apk asset
            val apkAssets = release.assets.filter { it.name.endsWith(".apk") }
            Log.d(TAG, "Found ${apkAssets.size} APK assets: ${apkAssets.map { it.name }}")

            val selectedApk = when {
                apkAssets.isEmpty() -> {
                    Log.w(TAG, "No APK asset found in release ${release.tagName}")
                    null
                }
                apkAssets.size == 1 -> {
                    val asset = apkAssets.first()
                    Log.d(TAG, "Single APK found, selecting: ${asset.name}")
                    asset
                }
                else -> {
                    // Multiple APKs: prioritize those containing "MusicGlass" and the version string
                    val version = release.tagName.removePrefix("v")
                    val prioritized = apkAssets.find { 
                        it.name.contains("MusicGlass", ignoreCase = true) && it.name.contains(version) 
                    } ?: apkAssets.find { 
                        it.name.contains("release", ignoreCase = true) && !it.name.contains("unsigned", ignoreCase = true)
                    } ?: apkAssets.find { 
                        it.name.contains("release", ignoreCase = true)
                    } ?: apkAssets.find { 
                        !it.name.contains("debug", ignoreCase = true)
                    } ?: apkAssets.first()
                    
                    Log.d(TAG, "Multiple APKs found, selected: ${prioritized.name} based on priority logic")
                    prioritized
                }
            }

            if (selectedApk == null) {
                _updateState.value = UpdateCheckState.NoUpdate
                return@withContext null
            }

            val currentVersion = BuildConfig.VERSION_NAME
            val comparison = compareVersions(release.tagName, currentVersion)
            val isUpdateAvailable = comparison > 0

            Log.d(TAG, "Version comparison: Installed=$currentVersion, Remote=${release.tagName} -> UpdateAvailable=$isUpdateAvailable")

            val updateInfo = UpdateInfo(
                latestVersion = release.tagName,
                currentVersion = currentVersion,
                releaseNotes = release.body ?: "",
                releaseName = release.name ?: release.tagName,
                apkDownloadUrl = selectedApk.browserDownloadUrl,
                apkSizeBytes = selectedApk.size
            )

            cachedUpdateInfo = updateInfo

            if (isUpdateAvailable) {
                // Check if user dismissed this version (only for non-forced checks)
                val dismissed = getDismissedVersion()
                if (!forceShow && dismissed == updateInfo.latestVersion) {
                    Log.d(TAG, "Update available (${updateInfo.latestVersion}) but dismissed by user")
                    _updateState.value = UpdateCheckState.NoUpdate
                    return@withContext null
                }
                Log.i(TAG, "Update confirmed: ${updateInfo.latestVersion} is available for download")
                _updateState.value = UpdateCheckState.UpdateAvailable(updateInfo)
                return@withContext updateInfo
            } else {
                Log.d(TAG, "Application is up to date (Installed: $currentVersion)")
                _updateState.value = UpdateCheckState.NoUpdate
                return@withContext null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Update check failed", e)
            _updateState.value = UpdateCheckState.Error(e.message ?: "Erreur inconnue")
            return@withContext null
        }
    }

    /**
     * Downloads the APK from the given URL and triggers the system installer.
     */
    suspend fun downloadAndInstall(updateInfo: UpdateInfo) = withContext(Dispatchers.IO) {
        val ctx = appContext ?: return@withContext
        try {
            _updateState.value = UpdateCheckState.Downloading(0f)
            _downloadProgress.value = 0f

            val updatesDir = File(ctx.getExternalFilesDir(null), "updates").apply { mkdirs() }
            val apkFile = File(updatesDir, "MusicGlass-${updateInfo.latestVersion}.apk")

            // Clean old APKs
            updatesDir.listFiles()?.filter { it.name != apkFile.name }?.forEach { it.delete() }

            val request = Request.Builder()
                .url(updateInfo.apkDownloadUrl)
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                _updateState.value = UpdateCheckState.Error("Échec du téléchargement (${response.code})")
                return@withContext
            }

            val responseBody = response.body ?: run {
                _updateState.value = UpdateCheckState.Error("Réponse vide")
                return@withContext
            }

            val totalBytes = responseBody.contentLength()
            var downloadedBytes = 0L

            responseBody.byteStream().use { input ->
                FileOutputStream(apkFile).use { output ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        downloadedBytes += bytesRead
                        val progress = if (totalBytes > 0) {
                            (downloadedBytes.toFloat() / totalBytes).coerceIn(0f, 1f)
                        } else 0f
                        _downloadProgress.value = progress
                        _updateState.value = UpdateCheckState.Downloading(progress)
                    }
                }
            }

            _updateState.value = UpdateCheckState.ReadyToInstall(apkFile, updateInfo)
            installApk(ctx, apkFile)

        } catch (e: Exception) {
            Log.e(TAG, "Download failed", e)
            _updateState.value = UpdateCheckState.Error("Erreur: ${e.message}")
        }
    }

    private fun installApk(context: Context, apkFile: File) {
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            apkFile
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
        }
        context.startActivity(intent)
    }

    /**
     * Checks whether the changelog for the current version should be shown
     * (i.e. the user just updated from a previous version).
     */
    fun shouldShowChangelog(): Boolean {
        val lastSeen = getLastSeenVersion() ?: return false  // First install — skip
        val current = BuildConfig.VERSION_NAME
        return compareVersions(current, lastSeen) > 0
    }

    /**
     * Returns the cached release notes (if update was recently checked).
     */
    fun getCachedUpdateInfo(): UpdateInfo? = cachedUpdateInfo

    fun resetState() {
        _updateState.value = UpdateCheckState.Idle
        _downloadProgress.value = 0f
    }
}

/**
 * Sealed hierarchy representing update-checking states.
 */
sealed class UpdateCheckState {
    object Idle : UpdateCheckState()
    object Checking : UpdateCheckState()
    object NoUpdate : UpdateCheckState()
    data class UpdateAvailable(val info: UpdateInfo) : UpdateCheckState()
    data class Downloading(val progress: Float) : UpdateCheckState()
    data class ReadyToInstall(val file: File, val info: UpdateInfo) : UpdateCheckState()
    data class Error(val message: String) : UpdateCheckState()
}
