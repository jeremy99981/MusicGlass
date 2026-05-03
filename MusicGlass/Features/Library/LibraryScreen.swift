import SwiftUI

struct LibraryScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AVPlayerEngine
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var viewModel: LibraryViewModel
    @State private var showSettings = false
    @AppStorage("musicglass.loginFlowInProgress") private var loginFlowInProgress = false

    var body: some View {
        NavigationStack {
            List {
                quickAccess
                ytPlaylistsSection
                favoritesSection
                historySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Bibliothèque")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Réglages")
                }
            }
            .task { viewModel.load() }
            .onAppear { viewModel.load() }
            .onReceive(container.authService.$cookies) { _ in
                viewModel.load()
            }
            .onReceive(container.authService.$dataSyncId) { _ in
                viewModel.load()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                if loginFlowInProgress, !container.authService.isAuthenticated {
                    showSettings = true
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsScreen(viewModel: SettingsViewModel(cacheManager: container.playbackCacheManager, authService: container.authService))
            }
            .navigationDestination(for: MusicDestination.self) { destination in
                destinationView(destination)
            }
        }
    }

    private var quickAccess: some View {
        Section {
            LibraryTile(
                systemImage: AppIcons.heartFill,
                title: "Favoris",
                subtitle: "\(viewModel.allFavorites.count) morceau\(viewModel.allFavorites.count > 1 ? "x" : "")",
                color: AppColors.accent
            )
            LibraryTile(
                systemImage: "clock.arrow.circlepath",
                title: "Historique",
                subtitle: "\(viewModel.allHistory.count) écoute\(viewModel.allHistory.count > 1 ? "s" : "") récente\(viewModel.allHistory.count > 1 ? "s" : "")",
                color: AppColors.secondaryAccent
            )
            LibraryTile(
                systemImage: "music.note.list",
                title: "Playlists locales",
                subtitle: "\(viewModel.playlists.count) playlist\(viewModel.playlists.count > 1 ? "s" : "")",
                color: .indigo
            )
        }
    }

    @ViewBuilder
    private var ytPlaylistsSection: some View {
        if !viewModel.ytPlaylists.isEmpty {
            Section("Mes playlists YouTube Music") {
                ForEach(viewModel.ytPlaylists) { playlist in
                    NavigationLink(value: MusicDestination.playlist(playlist.browseId ?? playlist.id)) {
                        HStack(spacing: 12) {
                            AsyncImage(url: playlist.thumbnails.first?.url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                default:
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray5))
                                        .overlay {
                                            Image(systemName: "music.note.list")
                                                .foregroundStyle(.secondary)
                                        }
                                }
                            }
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                if let trackCount = playlist.trackCount, trackCount > 0 {
                                    Text("\(trackCount) titres")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else if let author = playlist.author {
                                    Text(author)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        } else if viewModel.isLoadingYTLibrary {
            Section("Mes playlists YouTube Music") {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Chargement de votre bibliothèque...")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        Section("Favoris") {
            if viewModel.allFavorites.isEmpty {
                Text("Vos morceaux aimés apparaîtront ici.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.allFavorites.prefix(20)) { track in
                    TrackRow(track: track, isFavorite: true) {
                        player.play(track, queue: viewModel.allFavorites)
                    } onRadio: {
                        player.playRadio(from: track)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                }
                if viewModel.allFavorites.count > 20 {
                    Text("et \(viewModel.allFavorites.count - 20) autres morceaux...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section {
            if viewModel.allHistory.isEmpty {
                Text("Vos écoutes apparaîtront ici.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.allHistory.prefix(30)) { track in
                    TrackRow(track: track) {
                        player.play(track, queue: viewModel.allHistory)
                    } onRadio: {
                        player.playRadio(from: track)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                }
            }
            if !viewModel.history.isEmpty {
                Button(role: .destructive) {
                    viewModel.clearHistory()
                } label: {
                    Label("Effacer l'historique local", systemImage: "trash")
                }
            }
        } header: {
            Text("Écoutés récemment")
        }
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

private struct LibraryTile: View {
    var systemImage: String
    var title: String
    var subtitle: String
    var color: Color

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(color, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}
