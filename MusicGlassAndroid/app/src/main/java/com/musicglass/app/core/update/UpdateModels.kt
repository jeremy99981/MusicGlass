package com.musicglass.app.core.update

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Represents a GitHub Release fetched from the API.
 */
@Serializable
data class GitHubRelease(
    @SerialName("tag_name") val tagName: String,
    val name: String? = null,
    val body: String? = null,
    @SerialName("html_url") val htmlUrl: String? = null,
    @SerialName("published_at") val publishedAt: String? = null,
    val assets: List<GitHubAsset> = emptyList()
)

@Serializable
data class GitHubAsset(
    val name: String,
    @SerialName("browser_download_url") val browserDownloadUrl: String,
    val size: Long = 0,
    @SerialName("content_type") val contentType: String? = null
)

/**
 * The state exposed to the UI about an available update.
 */
data class UpdateInfo(
    val latestVersion: String,
    val currentVersion: String,
    val releaseNotes: String,
    val releaseName: String,
    val apkDownloadUrl: String,
    val apkSizeBytes: Long = 0
) {
    val isUpdateAvailable: Boolean
        get() = compareVersions(latestVersion, currentVersion) > 0
}

/**
 * Compares two semver-style version strings (e.g. "v1.2.0" vs "1.1.0").
 * Returns > 0 if v1 > v2, 0 if equal, < 0 if v1 < v2.
 * Robustly handles "v" prefix and ignores non-numeric suffixes (like -beta).
 */
fun compareVersions(v1: String, v2: String): Int {
    fun String.toVersionParts(): List<Int> {
        return this.removePrefix("v")
            .split("-")[0] // Ignore -beta, -rc etc.
            .split(".")
            .map { it.toIntOrNull() ?: 0 }
    }

    val parts1 = v1.toVersionParts()
    val parts2 = v2.toVersionParts()
    
    val maxLen = maxOf(parts1.size, parts2.size)
    for (i in 0 until maxLen) {
        val p1 = parts1.getOrElse(i) { 0 }
        val p2 = parts2.getOrElse(i) { 0 }
        if (p1 != p2) return p1 - p2
    }
    return 0
}
