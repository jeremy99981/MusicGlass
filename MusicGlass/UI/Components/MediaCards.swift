import SwiftUI

struct AlbumCard: View {
    var album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            ArtworkView(url: album.bestThumbnailURL, size: 146, cornerRadius: AppRadius.medium)
            Text(album.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 146, alignment: .leading)
            Text(album.artistLine.isEmpty ? "Album" : album.artistLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 146, alignment: .leading)
        }
    }
}

struct ArtistCard: View {
    var artist: Artist

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            ArtworkView(url: artist.bestThumbnailURL, size: 132, cornerRadius: 66)
            Text(artist.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 132)
        }
    }
}

struct PlaylistCard: View {
    var playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            ArtworkView(url: playlist.bestThumbnailURL, size: 146, cornerRadius: AppRadius.medium)
            Text(playlist.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 146, alignment: .leading)
            Text(playlist.author ?? "Playlist")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 146, alignment: .leading)
        }
    }
}

struct HomeItemCard: View {
    var item: HomeItem

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            ArtworkView(url: item.artworkURL, size: 152, cornerRadius: AppRadius.medium)
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 152, alignment: .leading)
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 152, alignment: .leading)
        }
    }
}
