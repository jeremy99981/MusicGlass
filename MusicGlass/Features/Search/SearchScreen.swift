import SwiftUI

struct SearchScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AVPlayerEngine
    @StateObject var viewModel: SearchViewModel
    @State private var favoriteIds = Set<String>()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.large) {
                        filterChips
                        suggestions
                        content
                    }
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.bottom, 140)
                }
            }
            .navigationTitle("Recherche")
            .searchable(text: $viewModel.query, prompt: "Morceaux, albums, artistes")
            .onSubmit(of: .search) { viewModel.queryChanged() }
            .onChange(of: viewModel.query) { _, _ in viewModel.queryChanged() }
            .task { reloadFavorites() }
            .navigationDestination(for: MusicDestination.self) { destination in
                switch destination {
                case .album(let browseId):
                    AlbumDetailScreen(viewModel: AlbumDetailViewModel(client: container.youTubeMusicClient, browseId: browseId))
                case .artist(let browseId):
                    ArtistDetailScreen(viewModel: ArtistDetailViewModel(client: container.youTubeMusicClient, browseId: browseId))
                case .playlist(let browseId):
                    PlaylistDetailScreen(viewModel: PlaylistDetailViewModel(client: container.youTubeMusicClient, browseId: browseId))
                }
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AppSpacing.small) {
                ForEach(SearchFilter.allCases) { filter in
                    Button {
                        viewModel.setFilter(filter)
                    } label: {
                        Text(filter.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(viewModel.filter == filter ? .white : .primary)
                            .background(viewModel.filter == filter ? AppColors.accent : .clear, in: Capsule())
                            .appGlass(tint: viewModel.filter == filter ? AppColors.accent.opacity(0.3) : nil, in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, AppSpacing.small)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var suggestions: some View {
        if !viewModel.suggestions.isEmpty && !viewModel.query.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: AppSpacing.small) {
                    ForEach(viewModel.suggestions.prefix(8), id: \.self) { suggestion in
                        Button {
                            viewModel.submitSuggestion(suggestion)
                        } label: {
                            Label(suggestion, systemImage: "sparkle.magnifyingglass")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .appGlass(in: Capsule(), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.query.isEmpty {
            EmptyStateView(systemImage: AppIcons.search, title: "Trouver votre musique", message: "Recherchez des morceaux, albums, artistes, playlists et vidéos.")
        } else if viewModel.isLoading && viewModel.result.isEmpty {
            LoadingSkeleton()
        } else if let error = viewModel.errorMessage {
            ErrorStateView(message: error) { viewModel.queryChanged() }
        } else if viewModel.result.isEmpty {
            EmptyStateView(systemImage: "music.note.list", title: "Aucun résultat", message: "Essayez une autre recherche.")
        } else {
            resultSections
        }
    }

    private var resultSections: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            if !viewModel.result.tracks.isEmpty {
                TrackSection(title: "Morceaux", tracks: viewModel.result.tracks, favoriteIds: favoriteIds, onPlay: play, onRadio: startRadio, onFavorite: toggleFavorite)
            }
            if !viewModel.result.albums.isEmpty {
                MediaHorizontalSection(title: "Albums") {
                    ForEach(viewModel.result.albums) { album in
                        NavigationLink(value: MusicDestination.album(album.browseId ?? album.id)) {
                            AlbumCard(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !viewModel.result.artists.isEmpty {
                MediaHorizontalSection(title: "Artistes") {
                    ForEach(viewModel.result.artists) { artist in
                        NavigationLink(value: MusicDestination.artist(artist.browseId ?? artist.id)) {
                            ArtistCard(artist: artist)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !viewModel.result.playlists.isEmpty {
                MediaHorizontalSection(title: "Playlists") {
                    ForEach(viewModel.result.playlists) { playlist in
                        NavigationLink(value: MusicDestination.playlist(playlist.browseId ?? playlist.id)) {
                            PlaylistCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !viewModel.result.videos.isEmpty {
                TrackSection(title: "Vidéos", tracks: viewModel.result.videos, favoriteIds: favoriteIds, onPlay: play, onRadio: startRadio, onFavorite: toggleFavorite)
            }
        }
    }

    private func play(_ track: Track) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        player.play(track, queue: viewModel.result.tracks + viewModel.result.videos)
    }

    private func startRadio(_ track: Track) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        player.playRadio(from: track)
    }

    private func toggleFavorite(_ track: Track) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let isLiked = (try? container.favoritesRepository.toggle(track)) ?? false
        reloadFavorites()
        guard container.authService.isAuthenticated else { return }
        Task {
            do {
                try await container.youTubeMusicClient.setLike(videoId: track.videoId, liked: isLiked)
            } catch {
                AppLogger.youtube.error("Failed to sync like with YouTube Music: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func reloadFavorites() {
        favoriteIds = Set((try? container.favoritesRepository.allFavorites().map(\.id)) ?? [])
    }
}

struct TrackSection: View {
    var title: String
    var tracks: [Track]
    var favoriteIds: Set<String>
    var onPlay: (Track) -> Void
    var onRadio: (Track) -> Void
    var onFavorite: (Track) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title)
                .font(AppTypography.sectionTitle)
            VStack(spacing: AppSpacing.small) {
                ForEach(tracks) { track in
                    TrackRow(track: track, isFavorite: favoriteIds.contains(track.id)) {
                        onPlay(track)
                    } onRadio: {
                        onRadio(track)
                    } onFavorite: {
                        onFavorite(track)
                    }
                }
            }
        }
    }
}

struct MediaHorizontalSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text(title)
                .font(AppTypography.sectionTitle)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: AppSpacing.medium) {
                    content
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
