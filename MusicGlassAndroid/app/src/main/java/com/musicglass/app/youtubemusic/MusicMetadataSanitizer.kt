package com.musicglass.app.youtubemusic

fun SongItem.cleanedMusicGlassMetadata(): SongItem {
    val cleanedArtists = artists
        .mapNotNull { artist ->
            val name = artist.name.trim()
            if (name.isBlank() || name.isGenericMusicGlassArtistLabel()) {
                null
            } else {
                artist.copy(name = name)
            }
        }
        .distinctBy { it.name.foldedMusicGlassMetadataKey() }

    return copy(artists = cleanedArtists)
}

fun String.isGenericMusicGlassArtistLabel(): Boolean {
    return foldedMusicGlassMetadataKey() in setOf(
        "album",
        "single",
        "ep",
        "song",
        "songs",
        "titre",
        "titres",
        "morceau",
        "morceaux",
        "video",
        "videos",
        "artist",
        "artiste",
        "playlist",
        "playlists"
    )
}

private fun String.foldedMusicGlassMetadataKey(): String {
    return java.text.Normalizer.normalize(this, java.text.Normalizer.Form.NFD)
        .replace(Regex("\\p{Mn}+"), "")
        .lowercase()
        .trim()
}
