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

fun SongItem.isSameQueueItemAs(other: SongItem?): Boolean {
    if (other == null) return false
    
    // 1. YouTube Music ID (videoId is stored in 'id')
    if (this.id.isNotBlank() && this.id == other.id) return true
    
    // 2. Browse ID
    if (!this.browseId.isNullOrBlank() && this.browseId == other.browseId) return true
    
    // 3. Fallback: Title + First Artist comparison (normalized)
    val thisTitle = this.title.foldedMusicGlassMetadataKey()
    val otherTitle = other.title.foldedMusicGlassMetadataKey()
    
    if (thisTitle.isNotBlank() && thisTitle == otherTitle) {
        val thisArtist = this.artists.firstOrNull()?.name?.foldedMusicGlassMetadataKey()
        val otherArtist = other.artists.firstOrNull()?.name?.foldedMusicGlassMetadataKey()
        
        if (thisArtist != null && thisArtist == otherArtist) return true
        if (thisArtist == null && otherArtist == null) return true
    }
    
    return false
}

private fun String.foldedMusicGlassMetadataKey(): String {
    return java.text.Normalizer.normalize(this, java.text.Normalizer.Form.NFD)
        .replace(Regex("\\p{Mn}+"), "")
        .lowercase()
        .trim()
}
