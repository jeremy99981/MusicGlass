import SwiftUI
import Speech
import AVFoundation
import AppIntents

struct SearchScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AVPlayerEngine
    @StateObject var viewModel: SearchViewModel
    @State private var favoriteIds = Set<String>()
    var playerDestination: Binding<MusicDestination?> = .constant(nil)
    @State private var navigationPath: [MusicDestination] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.large) {
                        filterChips
                        suggestions
                        content
                    }
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
                case .libraryArtists:
                    LibraryArtistsView()
                case .libraryArtist(let name):
                    LibraryArtistDetailView(artistName: name)
                }
            }
            .onChange(of: playerDestination.wrappedValue) { _, destination in
                guard let destination else { return }
                navigationPath.append(destination)
                playerDestination.wrappedValue = nil
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        pendingFullPlayer = false
                        showAISearch = true
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppColors.accent.gradient)
                            .padding(8)
                            .appGlass(in: Circle(), interactive: true)
                    }
                }
            }
            .sheet(isPresented: $showAISearch, onDismiss: {
                if let destination = pendingNavigation {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        navigationPath.append(destination)
                        pendingNavigation = nil
                    }
                }
                if pendingFullPlayer {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        player.shouldShowFullPlayer = true
                        pendingFullPlayer = false
                    }
                }
            }) {
                AIAssistantModalView(
                    container: container,
                    onFinish: { shouldOpenPlayer in
                        pendingFullPlayer = shouldOpenPlayer
                        showAISearch = false
                    },
                    onNavigateToArtist: { browseId, _ in
                        pendingNavigation = .artist(browseId)
                        showAISearch = false
                    },
                    onNavigateToAlbum: { browseId, _ in
                        pendingNavigation = .album(browseId)
                        showAISearch = false
                    },
                    onNavigateToPlaylist: { browseId, _ in
                        pendingNavigation = .playlist(browseId)
                        showAISearch = false
                    },
                    onSearch: { query in
                        showAISearch = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            viewModel.query = query
                            viewModel.queryChanged()
                        }
                    }
                )
                .environmentObject(container)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
            }
        }
    }

    @State private var showAISearch = false
    @State private var pendingFullPlayer = false
    @State private var pendingNavigation: MusicDestination? = nil

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
            .padding(.horizontal, AppSpacing.medium)
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
                .padding(.horizontal, AppSpacing.medium)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.query.isEmpty {
            EmptyStateView(systemImage: AppIcons.search, title: "Trouver votre musique", message: "Recherchez des morceaux, albums, artistes, playlists et vidéos.")
                .padding(.horizontal, AppSpacing.medium)
        } else if viewModel.isLoading && viewModel.result.isEmpty {
            LoadingSkeleton()
                .padding(.horizontal, AppSpacing.medium)
        } else if let error = viewModel.errorMessage {
            ErrorStateView(message: error) { viewModel.queryChanged() }
                .padding(.horizontal, AppSpacing.medium)
        } else if viewModel.result.isEmpty {
            EmptyStateView(systemImage: "music.note.list", title: "Aucun résultat", message: "Essayez une autre recherche.")
                .padding(.horizontal, AppSpacing.medium)
        } else {
            resultSections
        }
    }

    private var resultSections: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
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
            if !viewModel.result.tracks.isEmpty {
                TrackSection(title: viewModel.result.artists.isEmpty ? "Morceaux" : "Meilleurs titres", tracks: viewModel.result.tracks, favoriteIds: favoriteIds, onPlay: play, onRadio: startRadio, onFavorite: toggleFavorite)
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

// MARK: - AI Assistant UI

struct AIAssistantModalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: AIAssistantViewModel
    var onFinish: ((Bool) -> Void)?

    init(container: AppContainer,
         onFinish: ((Bool) -> Void)? = nil,
         onNavigateToArtist: ((String, String) -> Void)? = nil,
         onNavigateToAlbum: ((String, String) -> Void)? = nil,
         onNavigateToPlaylist: ((String, String) -> Void)? = nil,
         onSearch: ((String) -> Void)? = nil) {
        let vm = AIAssistantViewModel(container: container)
        vm.onNavigateToArtist = onNavigateToArtist
        vm.onNavigateToAlbum = onNavigateToAlbum
        vm.onNavigateToPlaylist = onNavigateToPlaylist
        vm.onSearch = onSearch
        _viewModel = StateObject(wrappedValue: vm)
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 999)
                .fill(.secondary.opacity(0.3))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            header
                .padding(.horizontal, 24)
                .padding(.top, 18)

            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
        )
        .onDisappear { viewModel.reset() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.accent, AppColors.accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Assistant IA")
                    .font(.title3.weight(.bold))
                Text("Recherche musicale intelligente")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.state {
        case .idle:
            idleContent
        case .checkingPermissions, .requestingSpeechPermission, .requestingMicrophonePermission:
            InitializingView(text: "Verification des autorisations...")
        case .startingAudio:
            InitializingView(text: "Preparation du micro...")
        case .listening:
            listeningContent
        case .processingSpeech, .thinking:
            InitializingView(text: "Analyse de votre demande...")
        case .resolving:
            InitializingView(text: "Recherche de la musique...")
        case .showingAlbumChoices(let question, let albums):
            albumChoicesContent(question: question, albums: albums)
        case .playing:
            playingContent
        case .textInput(let message):
            textInputContent(message: message)
        case .error(let msg):
            errorContent(message: msg)
        case .navigateToArtist, .navigateToAlbum, .navigateToPlaylist, .searchResults:
            navigatingContent
                .onAppear {
                    viewModel.executeNavigation()
                }
        case .chatResponse(let msg):
            chatResponseContent(message: msg)
        }
    }

    private var idleContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(AppColors.accent.gradient)
            }

            VStack(spacing: 8) {
                Text("Comment puis-je vous aider ?")
                    .font(.title3.weight(.semibold))
                Text("Dites ou ecrivez ce que vous voulez ecouter")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button {
                    Task { await viewModel.startAssistant() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18))
                        Text("Demarrer l'Assistant")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppColors.accent.gradient)
                )

                Button {
                    viewModel.setState(.textInput(nil), reason: "User chose text input")
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 16))
                        Text("Ecrire ma demande")
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.primary.opacity(0.1), lineWidth: 0.5)
                        )
                )
            }
        }
    }

    private var listeningContent: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.15))
                    .frame(width: 140, height: 140)

                WaveformView()
                    .frame(width: 100, height: 60)
            }

            VStack(spacing: 10) {
                if viewModel.transcript.isEmpty {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 8, height: 8)
                            .opacity(0.8)
                            .scaleEffect(1.0)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: true)
                        Text("Je vous ecoute...")
                            .font(.headline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(viewModel.transcript)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                        )
                }
            }

            HStack(spacing: 16) {
                Button {
                    viewModel.reset()
                } label: {
                    Text("Annuler")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
                        )
                )

                Button {
                    Task { await viewModel.finishListening() }
                } label: {
                    Text("Terminer")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppColors.accent.gradient)
                )
            }
        }
    }

    private var playingContent: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "music.note.list")
                    .font(.system(size: 36))
                    .foregroundStyle(AppColors.accent.gradient)
            }
            Text("Lecture en cours...")
                .font(.headline)
            Text("Votre musique est lancee")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                onFinish?(true)
            }
        }
    }

    private func albumChoicesContent(question: String, albums: [Album]) -> some View {
        VStack(spacing: 20) {
            Text(question)
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(albums) { album in
                        Button {
                            Task { await viewModel.selectAlbum(album) }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                AsyncImage(url: album.bestThumbnailURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.ultraThinMaterial)
                                }
                                .frame(width: 140, height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(.primary.opacity(0.06), lineWidth: 0.5)
                                )

                                Text(album.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                    .frame(width: 140, alignment: .leading)

                                Text(album.artists.first?.name ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 140, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }

            Button {
                viewModel.reset()
            } label: {
                Text("Annuler")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    private func textInputContent(message: String?) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "pencil.line")
                    .font(.system(size: 30))
                    .foregroundStyle(AppColors.accent.gradient)
            }

            if let message {
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }

            HStack(spacing: 0) {
                TextField("Artiste, album, humeur...", text: $viewModel.textInput)
                    .font(.body)
                    .padding(.leading, 16)
                    .padding(.vertical, 14)

                Button {
                    Task { await viewModel.processText(viewModel.textInput) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(viewModel.textInput.isEmpty ? .secondary : AppColors.accent)
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(viewModel.textInput.isEmpty)
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(viewModel.textInput.isEmpty ? .primary.opacity(0.08) : AppColors.accent.opacity(0.3), lineWidth: 1)
                    )
            )
            .animation(.easeInOut(duration: 0.25), value: viewModel.textInput.isEmpty)

            Button {
                viewModel.reset()
                Task { await viewModel.startAssistant() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                    Text("Reessayer le micro")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var navigatingContent: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Ouverture en cours...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func chatResponseContent(message: String) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(AppColors.accent.gradient)
            }
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)

            Button {
                viewModel.reset()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                    Text("Nouvelle recherche")
                        .font(.body.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColors.accent.gradient)
            )
        }
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
            }
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Button {
                viewModel.reset()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                    Text("Reessayer")
                        .font(.body.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColors.accent.gradient)
            )
        }
    }
}

struct InitializingView: View {
    let text: String
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct WaveformView: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<12) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.accent.gradient)
                    .frame(width: 4, height: 20 + sin(phase + Double(i)) * 15)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
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
                .padding(.horizontal, AppSpacing.medium)
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
            .padding(.horizontal, AppSpacing.medium)
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
                .padding(.horizontal, AppSpacing.medium)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: AppSpacing.medium) {
                    content
                }
                .padding(.horizontal, AppSpacing.medium)
            }
            .scrollIndicators(.hidden)
        }
    }
}


enum SpeechVoiceState {
    case idle
    case requestingSpeech
    case requestingMicrophone
    case ready
    case listening
    case error(String)
}

@MainActor
final class SpeechVoiceService: NSObject, ObservableObject {
    @Published private(set) var state: SpeechVoiceState = .idle

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    override init() {
        super.init()
        // Guard: check input availability (simulator has no hardware microphone)
        guard AVAudioSession.sharedInstance().isInputAvailable else {
            self.speechRecognizer = nil
            return
        }
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")) ?? SFSpeechRecognizer()
    }

    func requestPermissions() async -> Bool {
        // 1. Speech
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        // 2. Microphone
        let micStatus = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        return micStatus
    }

    func startListening(onPartialResult: @escaping (String) -> Void, onFinalResult: @escaping (String) -> Void, onError: @escaping (String) -> Void) async throws {
        // Stop any previous session
        stopListening()

        // Guard: no input hardware available (simulator)
        guard AVAudioSession.sharedInstance().isInputAvailable else {
            throw NSError(domain: "SpeechVoiceService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Aucun microphone disponible sur cet appareil."])
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw NSError(domain: "SpeechVoiceService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Erreur session audio: \(error.localizedDescription)"])
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw NSError(domain: "SpeechVoiceService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Reconnaissance vocale indisponible sur cet appareil"])
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            throw NSError(domain: "SpeechVoiceService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Impossible de creer la requete de reconnaissance."])
        }
        recognitionRequest.shouldReportPartialResults = true

        // SÉCURITÉ : Accès au nœud d'entrée peut crasher si non autorisé
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            throw NSError(domain: "SpeechVoiceService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Configuration micro invalide."])
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                if let result = result {
                    onPartialResult(result.bestTranscription.formattedString)
                    if result.isFinal {
                        onFinalResult(result.bestTranscription.formattedString)
                    }
                }

                if let error = error {
                    let nsError = error as NSError
                    // Ignorer les erreurs d'annulation normales
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 4 { return }
                    if nsError.domain == "NSURLErrorDomain" && nsError.code == -999 { return }

                    onError(error.localizedDescription)
                    self?.stopListening()
                }
            }
        }
    }

    func stopListening() {
        // Guard: only touch audio engine if input is available
        guard AVAudioSession.sharedInstance().isInputAvailable else { return }
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil

        // Nettoyage de la session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}


enum AIAssistantState: Equatable {
    case idle
    case checkingPermissions
    case requestingSpeechPermission
    case requestingMicrophonePermission
    case startingAudio
    case listening
    case processingSpeech
    case thinking
    case resolving
    case showingAlbumChoices(question: String, albums: [Album])
    case playing
    case textInput(String?)
    case error(String)
    case navigateToArtist(browseId: String, name: String)
    case navigateToAlbum(browseId: String, title: String)
    case navigateToPlaylist(browseId: String, title: String)
    case searchResults(query: String)
    case chatResponse(String)
}

@MainActor
final class AIAssistantViewModel: ObservableObject {
    @Published private(set) var state: AIAssistantState = .idle
    @Published var transcript = ""
    @Published var textInput = ""

    private let speechService = SpeechVoiceService()
    private let intentService = DeepSeekMusicIntentService()
    private let resolver: MusicAIResolver
    private let container: AppContainer

    private var isStarting = false
    private var isListening = false

    init(container: AppContainer) {
        self.container = container
        self.resolver = MusicAIResolver(client: container.youTubeMusicClient)
    }

    // Navigation callbacks
    var onNavigateToArtist: ((String, String) -> Void)?
    var onNavigateToAlbum: ((String, String) -> Void)?
    var onNavigateToPlaylist: ((String, String) -> Void)?
    var onSearch: ((String) -> Void)?


    func setState(_ newState: AIAssistantState, reason: String) {
        print("🎙️ [AI STATE] \(state) -> \(newState) | Reason: \(reason)")
        state = newState
    }

    func startAssistant() async {
        guard !isStarting else { return }
        guard !isListening else { return }

        isStarting = true
        defer { isStarting = false }

        transcript = ""
        setState(.checkingPermissions, reason: "User tapped start")

        let granted = await speechService.requestPermissions()
        guard granted else {
            setState(.textInput("Permissions refusées. Vous pouvez écrire votre demande."), reason: "Permissions denied")
            return
        }

        setState(.startingAudio, reason: "Permissions granted")

        do {
            try await speechService.startListening(
                onPartialResult: { [weak self] text in
                    Task { @MainActor in
                        self?.transcript = text
                        if self?.state != .listening {
                            self?.setState(.listening, reason: "Received first partial result")
                        }
                    }
                },
                onFinalResult: { [weak self] text in
                    Task { @MainActor in
                        self?.transcript = text
                        await self?.finishListening()
                    }
                },
                onError: { [weak self] errorMsg in
                    Task { @MainActor in
                        self?.setState(.textInput(errorMsg), reason: "Speech error")
                    }
                }
            )
            isListening = true
            setState(.listening, reason: "Audio engine started")
        } catch {
            let errorMsg = error.localizedDescription
            if errorMsg.contains("Aucun microphone") || errorMsg.contains("indisponible") {
                setState(.textInput("Microphone indisponible sur cet appareil. Vous pouvez ecrire votre demande."), reason: "No microphone")
            } else {
                setState(.error("Impossible de demarrer l'ecoute. Verifiez votre micro ou reessayez."), reason: "Start error: \(error)")
            }
        }
    }

    func finishListening() async {
        guard isListening else { return }
        isListening = false
        speechService.stopListening()

        if transcript.isEmpty {
            setState(.textInput("Je n'ai rien entendu. Réessayez ou écrivez."), reason: "Empty transcript")
        } else {
            await processText(transcript)
        }
    }

    func processText(_ text: String) async {
        setState(.thinking, reason: "Processing text: \(text)")
        do {
            let intent = try await intentService.parseIntent(from: text)
            setState(.resolving, reason: "Intent parsed: \(intent.type)")
            let resolution = try await resolver.resolve(intent: intent)
            await handleResolution(resolution)
        } catch {
            let userMsg = (error as? LocalizedError)?.errorDescription ?? "Je n'ai pas pu analyser votre demande. Réessayez."
            setState(.error(userMsg), reason: "DeepSeek error: \(error)")
        }
    }

    func selectAlbum(_ album: Album) async {
        guard let browseId = album.browseId else {
            setState(.error("Identifiant d'album manquant."), reason: "Missing browseId")
            return
        }
        setState(.resolving, reason: "User selected album: \(album.title)")
        do {
            let alb = try await container.youTubeMusicClient.getAlbum(browseId: browseId)
            await handleResolution(.playableAlbum(alb, alb.tracks))
        } catch {
            setState(.error("Impossible d'ouvrir l'album : \(error.localizedDescription)"), reason: "Album load error")
        }
    }

    private func handleResolution(_ resolution: MusicAIResolution) async {
        switch resolution {
        case .playableTrack(let track, let queue):
            executePlay(track, queue: queue)
        case .playableAlbum(_, let tracks):
            if let first = tracks.first {
                executePlay(first, queue: tracks)
            } else {
                setState(.error("L'album est vide."), reason: "Empty album")
            }
        case .playablePlaylist(_, let tracks):
            if let first = tracks.first {
                executePlay(first, queue: tracks)
            } else {
                setState(.error("La playlist est vide."), reason: "Empty playlist")
            }
        case .playableRadio(let track):
            executeRadio(track)
        case .albumList(let albums):
            setState(.showingAlbumChoices(question: "Quel album voulez-vous écouter ?", albums: albums), reason: "Ambiguous request, showing list")
        case .navigateToArtist(let browseId, let name):
            setState(.navigateToArtist(browseId: browseId, name: name), reason: "Navigate to artist")
        case .navigateToAlbum(let browseId, let title):
            setState(.navigateToAlbum(browseId: browseId, title: title), reason: "Navigate to album")
        case .navigateToPlaylist(let browseId, let title):
            setState(.navigateToPlaylist(browseId: browseId, title: title), reason: "Navigate to playlist")
        case .searchResults(let query):
            setState(.searchResults(query: query), reason: "Search results")
        case .openSearch(let q):
            setState(.searchResults(query: q), reason: "Open search")
        case .chatResponse(let msg):
            setState(.chatResponse(msg), reason: "Chat response")
        case .needsClarification(let msg):
            setState(.textInput(msg), reason: "Needs clarification")
        case .failure(let msg):
            setState(.error(msg), reason: "Resolution failure")
        }
    }

    private func executePlay(_ track: Track, queue: [Track]) {
        setState(.playing, reason: "Executing playback")
        Task { @MainActor in
            container.playerEngine.play(track, queue: queue)
        }
    }

    func executeNavigation() {
        switch state {
        case .navigateToArtist(let browseId, let name):
            onNavigateToArtist?(browseId, name)
        case .navigateToAlbum(let browseId, let title):
            onNavigateToAlbum?(browseId, title)
        case .navigateToPlaylist(let browseId, let title):
            onNavigateToPlaylist?(browseId, title)
        case .searchResults(let query):
            onSearch?(query)
        default: break
        }
    }

    private func executeRadio(_ track: Track) {
        setState(.playing, reason: "Executing radio")
        Task { @MainActor in
            container.playerEngine.playRadio(from: track)
        }
    }

    func reset() {
        speechService.stopListening()
        isListening = false
        transcript = ""
        textInput = ""
        setState(.idle, reason: "Reset called")
    }
}
