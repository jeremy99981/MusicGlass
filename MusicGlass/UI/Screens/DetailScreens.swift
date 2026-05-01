import SwiftUI

struct AlbumDetailScreen: View {
    @EnvironmentObject private var player: AVPlayerEngine
    @StateObject var viewModel: AlbumDetailViewModel

    var body: some View {
        DetailScaffold(isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage, retry: viewModel.load) {
            if let album = viewModel.album {
                DetailHeader(
                    artworkURL: album.bestThumbnailURL,
                    title: album.title,
                    subtitle: [album.artistLine, album.year.map(String.init)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - "),
                    play: { play(album.tracks.first, queue: album.tracks) },
                    shuffle: { play(album.tracks.randomElement(), queue: album.tracks) }
                )
                TrackList(tracks: album.tracks, onRadio: { player.playRadio(from: $0) }) { track in
                    player.play(track, queue: album.tracks)
                }
            }
        }
        .navigationTitle(viewModel.album?.title ?? "Album")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.load() }
    }

    private func play(_ track: Track?, queue: [Track]) {
        guard let track else { return }
        player.play(track, queue: queue)
    }
}

struct ArtistDetailScreen: View {
    @EnvironmentObject private var player: AVPlayerEngine
    @StateObject var viewModel: ArtistDetailViewModel

    var body: some View {
        DetailScaffold(isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage, retry: viewModel.load) {
            if let page = viewModel.page {
                DetailHeader(
                    artworkURL: page.artist.bestThumbnailURL,
                    title: page.artist.name,
                    subtitle: "Artiste",
                    play: { play(page.topTracks.first, queue: page.topTracks) },
                    shuffle: { play(page.topTracks.randomElement(), queue: page.topTracks) }
                )
                if !page.topTracks.isEmpty {
                    TrackList(title: "Titres populaires", tracks: page.topTracks, onRadio: { player.playRadio(from: $0) }) { track in
                        player.play(track, queue: page.topTracks)
                    }
                }
                if !page.albums.isEmpty {
                    MediaHorizontalSection(title: "Albums") {
                        ForEach(page.albums) { album in
                            NavigationLink(value: MusicDestination.album(album.browseId ?? album.id)) {
                                AlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.page?.artist.name ?? "Artiste")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.load() }
    }

    private func play(_ track: Track?, queue: [Track]) {
        guard let track else { return }
        player.play(track, queue: queue)
    }
}

struct PlaylistDetailScreen: View {
    @EnvironmentObject private var player: AVPlayerEngine
    @StateObject var viewModel: PlaylistDetailViewModel

    var body: some View {
        DetailScaffold(isLoading: viewModel.isLoading, errorMessage: viewModel.errorMessage, retry: viewModel.load) {
            if let playlist = viewModel.playlist {
                DetailHeader(
                    artworkURL: playlist.bestThumbnailURL,
                    title: playlist.title,
                    subtitle: playlist.author ?? "\(playlist.trackCount ?? playlist.tracks.count) morceaux",
                    play: { play(playlist.tracks.first, queue: playlist.tracks) },
                    shuffle: { play(playlist.tracks.randomElement(), queue: playlist.tracks) }
                )
                if let description = playlist.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppSpacing.medium)
                }
                TrackList(tracks: playlist.tracks, animateArtworkUpdates: viewModel.isRefreshingArtwork, onRadio: { player.playRadio(from: $0) }) { track in
                    player.play(track, queue: playlist.tracks)
                }
            }
        }
        .navigationTitle(viewModel.playlist?.title ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.load() }
    }

    private func play(_ track: Track?, queue: [Track]) {
        guard let track else { return }
        player.play(track, queue: queue)
    }
}

private struct DetailScaffold<Content: View>: View {
    var isLoading: Bool
    var errorMessage: String?
    var retry: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    if isLoading {
                        LoadingSkeleton(rows: 8)
                    } else if let errorMessage {
                        ErrorStateView(message: errorMessage, retry: retry)
                    } else {
                        content
                    }
                }
                .padding(.bottom, 120)
            }
        }
    }
}

private struct DetailHeader: View {
    var artworkURL: URL?
    var title: String
    var subtitle: String
    var play: () -> Void
    var shuffle: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            ArtworkView(url: artworkURL, size: 210, cornerRadius: 26)
            VStack(spacing: 5) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: AppSpacing.medium) {
                Button(action: play) {
                    Label("Lecture", systemImage: AppIcons.play)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: shuffle) {
                    Label("Aléatoire", systemImage: AppIcons.shuffle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal, AppSpacing.medium)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.large)
    }
}

private struct TrackList: View {
    var title: String?
    var tracks: [Track]
    var animateArtworkUpdates = false
    var onRadio: (Track) -> Void
    var onPlay: (Track) -> Void

    init(title: String? = nil, tracks: [Track], animateArtworkUpdates: Bool = false, onRadio: @escaping (Track) -> Void, onPlay: @escaping (Track) -> Void) {
        self.title = title
        self.tracks = tracks
        self.animateArtworkUpdates = animateArtworkUpdates
        self.onRadio = onRadio
        self.onPlay = onPlay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            if let title {
                Text(title)
                    .font(AppTypography.sectionTitle)
                    .padding(.horizontal, AppSpacing.medium)
            }
            if tracks.isEmpty {
                EmptyStateView(systemImage: "music.note", title: "Aucun titre", message: "Cette page ne contient pas de morceaux jouables.")
            } else {
                ForEach(tracks) { track in
                    TrackRow(track: track, animateArtworkUpdates: animateArtworkUpdates) {
                        onPlay(track)
                    } onRadio: {
                        onRadio(track)
                    }
                        .padding(.horizontal, AppSpacing.medium)
                }
            }
        }
    }
}
