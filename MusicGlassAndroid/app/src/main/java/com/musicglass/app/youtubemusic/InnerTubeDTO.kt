package com.musicglass.app.youtubemusic

import kotlinx.serialization.Serializable

@Serializable
data class InnerTubeContext(
    val client: InnerTubeClientInfo,
    val user: InnerTubeUserInfo = InnerTubeUserInfo()
)

@Serializable
data class InnerTubeUserInfo(
    val onBehalfOfUser: String? = null
)

@Serializable
data class InnerTubeClientInfo(
    val clientName: String = "WEB_REMIX",
    val clientVersion: String = "1.20260213.01.00",
    val hl: String = "en",
    val gl: String = "US",
    val visitorData: String? = null,
    val osName: String? = null,
    val osVersion: String? = null,
    val deviceMake: String? = null,
    val deviceModel: String? = null
)

@Serializable
data class InnerTubeSearchRequest(
    val context: InnerTubeContext = InnerTubeContext(InnerTubeClientInfo()),
    val query: String,
    val params: String? = null
)

@Serializable
data class InnerTubeHomeRequest(
    val context: InnerTubeContext = InnerTubeContext(InnerTubeClientInfo()),
    val browseId: String = "FEmusic_home"
)

@Serializable
enum class ItemType {
    SONG, PLAYLIST, ALBUM, ARTIST
}

@Serializable
data class SongItem(
    val id: String,
    val type: ItemType,
    val title: String,
    val artists: List<ArtistInfo>,
    val album: AlbumInfo?,
    val thumbnails: List<Thumbnail>,
    val browseId: String? = null,
    val durationSeconds: Long? = null
)

@Serializable
data class ArtistInfo(
    val name: String,
    val browseId: String? = null
)

@Serializable
data class AlbumInfo(
    val name: String,
    val browseId: String? = null,
    val thumbnails: List<Thumbnail> = emptyList()
)

@Serializable
data class Thumbnail(
    val url: String,
    val width: Int,
    val height: Int
)

@Serializable
data class HomeSection(
    val title: String,
    val items: List<SongItem>
)

@Serializable
data class InnerTubePlayerRequest(
    val context: InnerTubeContext = InnerTubeContext(
        InnerTubeClientInfo(
            clientName = "ANDROID_VR",
            clientVersion = "1.43.32",
            osName = "Android",
            osVersion = "12",
            deviceMake = "Oculus",
            deviceModel = "Quest 3"
        )
    ),
    val videoId: String
)

@Serializable
data class InnerTubePlayerRequestTV(
    val context: InnerTubeContext = InnerTubeContext(
        InnerTubeClientInfo(
            clientName = "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
            clientVersion = "2.0"
        )
    ),
    val videoId: String
)

data class PlayerFormat(
    val itag: Int,
    val url: String?,
    val mimeType: String,
    val bitrate: Int,
    val audioQuality: String?
)

data class PlayerPayload(
    val videoId: String,
    val title: String,
    val author: String?,
    val durationSeconds: Long?,
    val thumbnails: List<Thumbnail>,
    val formats: List<PlayerFormat>,
    val playabilityStatus: String,
    val hlsManifestUrl: String?,
    val serverAbrStreamingUrl: String?,
    val reason: String?
)

data class PlaylistDetails(
    val id: String,
    val title: String,
    val author: String?,
    val thumbnails: List<Thumbnail>,
    val tracks: List<SongItem>
)

data class ArtistPage(
    val id: String,
    val name: String,
    val thumbnails: List<Thumbnail>,
    val topTracks: List<SongItem>,
    val albums: List<SongItem>
)

fun List<Thumbnail>.bestThumbnailUrl(): String? {
    return this.maxByOrNull { thumbnail ->
        val width = thumbnail.width.toLong()
        val height = thumbnail.height.toLong()
        val area = (width * height).coerceAtLeast(1L)
        val aspectRatio = if (height > 0) width.toDouble() / height.toDouble() else 1.0
        val aspectPenalty = kotlin.math.abs(aspectRatio - 1.0) * 1_000_000.0
        val squareBonus = if (aspectRatio in 0.9..1.12) 8_000_000.0 else 0.0
        area + squareBonus - aspectPenalty
    }?.url
}
