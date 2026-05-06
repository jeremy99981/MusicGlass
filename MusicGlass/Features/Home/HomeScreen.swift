import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AVPlayerEngine
    @StateObject var viewModel: HomeViewModel
    var playerDestination: Binding<MusicDestination?> = .constant(nil)
    @State private var navigationPath: [MusicDestination] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                background
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                        header
                        content
                    }
                    .padding(.top, AppSpacing.medium)
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { viewModel.loadIfNeeded() }
            .onAppear { viewModel.refreshRecentlyPlayedSection() }
            .refreshable { viewModel.load() }
            .onReceive(container.authService.$dataSyncId) { _ in
                viewModel.load()
            }
            .navigationDestination(for: MusicDestination.self) { destination in
                destinationView(destination)
            }
            .onChange(of: playerDestination.wrappedValue) { _, destination in
                guard let destination else { return }
                navigationPath.append(destination)
                playerDestination.wrappedValue = nil
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                AppColors.accent.opacity(0.08),
                AppColors.secondaryAccent.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(greeting)
                .font(AppTypography.largeTitle)
                .foregroundStyle(.primary)
            Text("Recommandations, playlists du moment et découvertes pour vous")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppSpacing.medium)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.feed.sections.isEmpty {
            LoadingSkeleton(rows: 7)
        } else if let error = viewModel.errorMessage, viewModel.feed.sections.isEmpty {
            ErrorStateView(message: error) { viewModel.load() }
        } else {
            ForEach(viewModel.feed.sections) { section in
                HomeSectionView(
                    section: section,
                    action: { item in
                        handle(item)
                    },
                    radioAction: { track in
                        startRadio(from: track)
                    }
                )
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return switch hour {
        case 5..<12: "Bonjour"
        case 12..<18: "Bon après-midi"
        default: "Bonsoir"
        }
    }

    private func handle(_ item: HomeItem) {
        switch item {
        case .track(let track):
            let tracks = viewModel.feed.sections.flatMap { section in
                section.items.compactMap { if case .track(let track) = $0 { track } else { nil } }
            }
            player.play(track, queue: tracks)
        case .album, .artist, .playlist:
            break
        }
    }

    private func startRadio(from track: Track) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        player.playRadio(from: track)
    }

    @ViewBuilder
    private func destinationView(_ destination: MusicDestination) -> some View {
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

private struct HomeSectionView: View {
    var section: HomeSection
    var action: (HomeItem) -> Void
    var radioAction: (Track) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text(section.title.musicGlassFrenchSectionTitle)
                .font(AppTypography.sectionTitle)
                .padding(.horizontal, AppSpacing.medium)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: AppSpacing.medium) {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        homeCard(for: item)
                    }
                }
                .padding(.horizontal, AppSpacing.medium)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func homeCard(for item: HomeItem) -> some View {
        switch item {
        case .track(let track):
            Button {
                action(.track(track))
            } label: {
                HomeItemCard(item: .track(track))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    action(.track(track))
                } label: {
                    Label("Lecture", systemImage: AppIcons.play)
                }
                Button {
                    radioAction(track)
                } label: {
                    Label("Lancer la radio", systemImage: "dot.radiowaves.left.and.right")
                }
            }
        case .album(let album):
            NavigationLink(value: MusicDestination.album(album.browseId ?? album.id)) {
                HomeItemCard(item: item)
            }
            .buttonStyle(.plain)
        case .artist(let artist):
            NavigationLink(value: MusicDestination.artist(artist.browseId ?? artist.id)) {
                HomeItemCard(item: item)
            }
            .buttonStyle(.plain)
        case .playlist(let playlist):
            NavigationLink(value: MusicDestination.playlist(playlist.browseId ?? playlist.id)) {
                HomeItemCard(item: item)
            }
            .buttonStyle(.plain)
        }
    }
}

private extension String {
    var musicGlassFrenchSectionTitle: String {
        switch self.lowercased() {
        case "recently played":
            return "Écoutés récemment"
        case "quick picks":
            return "Suggestions rapides"
        case "suggested albums":
            return "Albums suggérés"
        case "trending":
            return "Tendances"
        case "recommendations":
            return "Recommandations"
        case "playlists":
            return "Playlists"
        default:
            return self
        }
    }
}
