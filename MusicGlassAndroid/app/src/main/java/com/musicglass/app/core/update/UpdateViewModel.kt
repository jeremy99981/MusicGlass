package com.musicglass.app.core.update

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.musicglass.app.BuildConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * ViewModel that orchestrates update checking, download,
 * and changelog display logic.
 */
class UpdateViewModel(application: Application) : AndroidViewModel(application) {

    val updateState = UpdateRepository.updateState
    val downloadProgress = UpdateRepository.downloadProgress

    // Controls whether the update dialog is visible
    private val _showUpdateDialog = MutableStateFlow(false)
    val showUpdateDialog: StateFlow<Boolean> = _showUpdateDialog

    // Controls whether the changelog dialog is visible
    private val _showChangelogDialog = MutableStateFlow(false)
    val showChangelogDialog: StateFlow<Boolean> = _showChangelogDialog

    // Cached release notes for the changelog dialog
    private val _changelogNotes = MutableStateFlow("")
    val changelogNotes: StateFlow<String> = _changelogNotes

    /**
     * Called once at app startup to:
     * 1. Show changelog if the user just updated to a new version
     * 2. Check GitHub for new updates
     */
    fun onAppStart() {
        // 1. Check if we should show the changelog (user just installed a new version)
        if (UpdateRepository.shouldShowChangelog()) {
            // Fetch release notes for the current version to display
            viewModelScope.launch {
                val info = UpdateRepository.checkForUpdate(forceShow = false)
                // The cached info might be for a *newer* version, not the current one.
                // For the changelog, we need the notes for the CURRENT version.
                // We'll fetch the release that matches the current version.
                fetchChangelogForCurrentVersion()
            }
        } else {
            // Mark current version as seen (first install case)
            if (UpdateRepository.getLastSeenVersion() == null) {
                UpdateRepository.markCurrentVersionSeen()
            }
            // 2. Check for updates in the background
            checkForUpdateSilently()
        }
    }

    /**
     * Fetches the changelog for the current app version from GitHub.
     */
    private fun fetchChangelogForCurrentVersion() {
        viewModelScope.launch {
            try {
                val repo = BuildConfig.GITHUB_REPO
                val version = BuildConfig.VERSION_NAME
                val url = "https://api.github.com/repos/$repo/releases/tags/v$version"

                val client = okhttp3.OkHttpClient()
                val request = okhttp3.Request.Builder()
                    .url(url)
                    .header("Accept", "application/vnd.github+json")
                    .get()
                    .build()

                val response = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    client.newCall(request).execute()
                }

                if (response.isSuccessful) {
                    val body = response.body?.string()
                    if (body != null) {
                        val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
                        val release = json.decodeFromString<GitHubRelease>(body)
                        _changelogNotes.value = release.body ?: ""
                    }
                }

                // Also try without 'v' prefix
                if (_changelogNotes.value.isEmpty()) {
                    val url2 = "https://api.github.com/repos/$repo/releases/tags/$version"
                    val request2 = okhttp3.Request.Builder()
                        .url(url2)
                        .header("Accept", "application/vnd.github+json")
                        .get()
                        .build()
                    val response2 = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                        client.newCall(request2).execute()
                    }
                    if (response2.isSuccessful) {
                        val body2 = response2.body?.string()
                        if (body2 != null) {
                            val json2 = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
                            val release2 = json2.decodeFromString<GitHubRelease>(body2)
                            _changelogNotes.value = release2.body ?: ""
                        }
                    }
                }
            } catch (_: Exception) {
                // Changelog fetch is best-effort
            }

            // Show the dialog regardless
            _showChangelogDialog.value = true
            UpdateRepository.markCurrentVersionSeen()
        }
    }

    /**
     * Silently checks for updates (startup check).
     * Only shows the dialog if an update is available and not dismissed.
     */
    fun checkForUpdateSilently() {
        viewModelScope.launch {
            val info = UpdateRepository.checkForUpdate(forceShow = false)
            if (info != null && info.isUpdateAvailable) {
                _showUpdateDialog.value = true
            }
        }
    }

    /**
     * Force check for updates (from Settings).
     * Always shows result even if previously dismissed.
     */
    fun checkForUpdateFromSettings() {
        viewModelScope.launch {
            UpdateRepository.resetState()
            val info = UpdateRepository.checkForUpdate(forceShow = true)
            if (info != null && info.isUpdateAvailable) {
                _showUpdateDialog.value = true
            }
        }
    }

    /**
     * Manually shows the update dialog (e.g. if an update was already found).
     */
    fun showUpdateDialog() {
        _showUpdateDialog.value = true
    }

    /**
     * Starts the APK download and installation.
     */
    fun downloadUpdate(updateInfo: UpdateInfo) {
        viewModelScope.launch {
            UpdateRepository.downloadAndInstall(updateInfo)
        }
    }

    /**
     * Dismisses the update dialog and marks the version as dismissed.
     */
    fun dismissUpdateDialog() {
        val state = updateState.value
        if (state is UpdateCheckState.UpdateAvailable) {
            UpdateRepository.dismissVersion(state.info.latestVersion)
        }
        _showUpdateDialog.value = false
        UpdateRepository.resetState()
    }

    /**
     * Dismisses the changelog dialog.
     */
    fun dismissChangelogDialog() {
        _showChangelogDialog.value = false
    }
}
