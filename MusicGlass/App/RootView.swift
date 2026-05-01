import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AVPlayerEngine
    @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer = false
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.system.rawValue
    @State private var selectedTab: AppTab = .home
    @State private var activePlayerSheet: PlayerSheet?
    @State private var homeViewModel: HomeViewModel?
    @State private var searchViewModel: SearchViewModel?
    @State private var libraryViewModel: LibraryViewModel?
    @Namespace private var playerNamespace
    #if DEBUG
    private let shouldAutoOpenDebugPlayer = ProcessInfo.processInfo.environment["MUSICGLASS_DEBUG_OPEN_PLAYER"] == "1"
    #endif

    var body: some View {
        Group {
            if hasAcceptedDisclaimer {
                tabRoot
            } else {
                DisclaimerView {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                        hasAcceptedDisclaimer = true
                    }
                }
            }
        }
        .task {
            configureViewModelsIfNeeded()
        }
        .preferredColorScheme(AppTheme(rawValue: appThemeRawValue)?.colorScheme)
        #if DEBUG
        .task(id: player.currentTrack?.id) {
            guard shouldAutoOpenDebugPlayer,
                  hasAcceptedDisclaimer,
                  player.currentTrack != nil,
                  activePlayerSheet == nil
            else { return }
            try? await Task.sleep(for: .milliseconds(400))
            activePlayerSheet = .fullPlayer
        }
        #endif
    }

    private var tabRoot: some View {
        ZStack(alignment: .bottom) {
            if let homeViewModel, let searchViewModel, let libraryViewModel {
                TabView(selection: $selectedTab) {
                    HomeScreen(viewModel: homeViewModel)
                        .tabItem { Label("Accueil", systemImage: "house.fill") }
                        .tag(AppTab.home)

                    SearchScreen(viewModel: searchViewModel)
                        .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
                        .tag(AppTab.search)

                    LibraryScreen(
                        viewModel: libraryViewModel
                    )
                    .tabItem { Label("Bibliothèque", systemImage: "square.stack.fill") }
                    .tag(AppTab.library)
                }
            } else {
                ProgressView()
            }

            if player.currentTrack != nil {
                MiniPlayer(namespace: playerNamespace) {
                    activePlayerSheet = .fullPlayer
                }
                .padding(.horizontal, AppSpacing.medium)
                .padding(.bottom, 56)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: player.currentTrack?.id)
        .fullScreenCover(isPresented: isFullPlayerPresented) {
            FullPlayerScreen(namespace: playerNamespace) {
                activePlayerSheet = nil
            } showQueue: {
                activePlayerSheet = .queue
            } showLyrics: { track in
                activePlayerSheet = .lyrics(track)
            }
        }
        .sheet(item: secondaryPlayerSheet) { sheet in
            switch sheet {
            case .queue:
                QueueScreen()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .lyrics(let track):
                LyricsScreen(viewModel: LyricsViewModel(client: container.youTubeMusicClient, track: track))
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .fullPlayer:
                EmptyView()
            }
        }
    }

    private var isFullPlayerPresented: Binding<Bool> {
        Binding(
            get: {
                guard let activePlayerSheet else { return false }
                if case .fullPlayer = activePlayerSheet {
                    return true
                }
                return false
            },
            set: { isPresented in
                if !isPresented, case .fullPlayer = activePlayerSheet {
                    activePlayerSheet = nil
                }
            }
        )
    }

    private var secondaryPlayerSheet: Binding<PlayerSheet?> {
        Binding(
            get: {
                guard let activePlayerSheet else { return nil }
                switch activePlayerSheet {
                case .queue, .lyrics:
                    return activePlayerSheet
                case .fullPlayer:
                    return nil
                }
            },
            set: { activePlayerSheet = $0 }
        )
    }

    private func configureViewModelsIfNeeded() {
        guard homeViewModel == nil || searchViewModel == nil || libraryViewModel == nil else { return }
        homeViewModel = HomeViewModel(client: container.youTubeMusicClient, historyRepository: container.historyRepository, authService: container.authService)
        searchViewModel = SearchViewModel(client: container.youTubeMusicClient)
        libraryViewModel = LibraryViewModel(
            favoritesRepository: container.favoritesRepository,
            historyRepository: container.historyRepository,
            playlistRepository: container.playlistRepository,
            youTubeMusicClient: container.youTubeMusicClient,
            authService: container.authService
        )
    }
}

private enum AppTheme: String {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
