import SwiftUI

struct LibraryScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AVPlayerEngine
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var viewModel: LibraryViewModel
    var playerDestination: Binding<MusicDestination?> = .constant(nil)
    @State private var navigationPath: [MusicDestination] = []
    
    // Pour simuler des sections non encore implémentées mais prévues
    @State private var showComingSoon = false
    @State private var comingSoonTitle = ""

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .top) {
                background
                
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                        header
                        
                        // Résumé rapide
                        quickStatsGrid
                        
                        // Actions principales
                        quickActionsGrid
                        
                        // Mes Playlists
                        playlistsSection
                        
                        // Récemment écoutés (version compacte car l'historique complet est dans Profil)
                        recentlyPlayedSection
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { viewModel.load() }
            .onAppear { viewModel.load() }
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
            .alert(comingSoonTitle, isPresented: $showComingSoon) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Cette fonctionnalité de bibliothèque sera disponible dans une prochaine mise à jour.")
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Bibliothèque")
                .font(AppTypography.largeTitle)
                .foregroundStyle(.primary)
            Text("Votre musique, vos playlists, vos favoris.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppSpacing.medium)
    }

    private var quickStatsGrid: some View {
        HStack(spacing: AppSpacing.medium) {
            statCard(
                title: "Titres aimés",
                count: viewModel.allFavorites.count,
                icon: AppIcons.heartFill,
                color: AppColors.accent
            )
            statCard(
                title: "Playlists",
                count: viewModel.playlists.count + viewModel.ytPlaylists.count,
                icon: "music.note.list",
                color: .indigo
            )
        }
        .padding(.horizontal, AppSpacing.medium)
    }

    private func statCard(title: String, count: Int, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color)
                }
                Spacer()
                Text("\(count)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .padding(AppSpacing.medium)
        .appGlass(in: RoundedRectangle(cornerRadius: 24))
    }

    private var quickActionsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.medium) {
            quickActionTile(title: "Artistes", icon: "person.2.fill", color: .orange) {
                navigationPath.append(.libraryArtists)
            }
            quickActionTile(title: "Albums", icon: "rectangle.stack.fill", color: .purple) {
                comingSoonTitle = "Albums"
                showComingSoon = true
            }
            quickActionTile(title: "Téléchargements", icon: "arrow.down.circle.fill", color: .green) {
                comingSoonTitle = "Téléchargements"
                showComingSoon = true
            }
            quickActionTile(title: "Historique", icon: "clock.fill", color: .blue) {
                // Raccourci vers la page historique existante (via le playerDestination ou un état de profil)
                // Pour simplifier ici, on pourrait ouvrir la page historique si on avait une route directe.
                // Mais l'historique complet est dans Profil. On laisse un placeholder utile.
                comingSoonTitle = "Historique détaillé"
                showComingSoon = true
            }
        }
        .padding(.horizontal, AppSpacing.medium)
    }

    private func quickActionTile(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.medium)
            .frame(height: 56)
            .appGlass(in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                Text("Mes playlists")
                    .font(AppTypography.sectionTitle)
                Spacer()
                if !viewModel.ytPlaylists.isEmpty || !viewModel.playlists.isEmpty {
                    Text("\(viewModel.ytPlaylists.count + viewModel.playlists.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.1), in: Capsule())
                }
            }
            .padding(.horizontal, AppSpacing.medium)
            
            if viewModel.isLoadingYTLibrary && viewModel.ytPlaylists.isEmpty {
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Chargement...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppSpacing.medium)
            } else if viewModel.ytPlaylists.isEmpty && viewModel.playlists.isEmpty {
                emptySectionCard(text: "Aucune playlist trouvée.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.medium) {
                        // YouTube Playlists
                        ForEach(viewModel.ytPlaylists) { playlist in
                            playlistCard(
                                title: playlist.title,
                                subtitle: "\(playlist.trackCount ?? 0) titres",
                                imageURL: playlist.thumbnails.first?.url,
                                destination: .playlist(playlist.browseId ?? playlist.id),
                                source: "YT Music"
                            )
                        }
                        
                        // Local Playlists
                        ForEach(viewModel.playlists) { playlist in
                            playlistCard(
                                title: playlist.title,
                                subtitle: "Playlist locale",
                                imageURL: nil, // On pourrait ajouter une mosaïque plus tard
                                destination: .playlist(playlist.id),
                                source: "Local"
                            )
                        }
                    }
                    .padding(.horizontal, AppSpacing.medium)
                }
            }
        }
    }

    private func playlistCard(title: String, subtitle: String, imageURL: URL?, destination: MusicDestination, source: String) -> some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    ArtworkView(url: imageURL, size: 140, cornerRadius: 16)
                        .frame(width: 140, height: 140)
                    
                    Text(source)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 140, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("Écoutés récemment")
                .font(AppTypography.sectionTitle)
                .padding(.horizontal, AppSpacing.medium)
            
            if viewModel.allHistory.isEmpty {
                emptySectionCard(text: "Votre historique apparaîtra ici.")
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.allHistory.prefix(5)) { track in
                        TrackRow(track: track) {
                            player.play(track, queue: viewModel.allHistory)
                        } onRadio: {
                            player.playRadio(from: track)
                        }
                        .padding(.horizontal, AppSpacing.medium)
                        .padding(.vertical, 8)
                        
                        if track.id != viewModel.allHistory.prefix(5).last?.id {
                            Divider()
                                .padding(.leading, 80)
                                .opacity(0.5)
                        }
                    }
                }
                .appGlass(in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, AppSpacing.medium)
            }
        }
    }

    private func emptySectionCard(text: String) -> some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(AppSpacing.medium)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, AppSpacing.medium)
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
        case .libraryArtists:
            LibraryArtistsView()
        case .libraryArtist(let name):
            LibraryArtistDetailView(artistName: name)
        }
    }
}

