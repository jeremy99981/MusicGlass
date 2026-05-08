import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AVPlayerEngine
    @StateObject var viewModel: HomeViewModel
    var playerDestination: Binding<MusicDestination?> = .constant(nil)
    @State private var navigationPath: [MusicDestination] = []
    @State private var showsNavigationChrome = false
    @State private var isProfileMenuPresented = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .top) {
                background
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                        header
                        content
                    }
                    .padding(.top, 12) // Optimisé pour Dynamic Island
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
                .homeScrollChromeTracking(isVisible: $showsNavigationChrome)
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                HomeScrollChrome(title: viewModel.greeting, isVisible: showsNavigationChrome)
                    .allowsHitTesting(false)
            }
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
            .sheet(isPresented: $isProfileMenuPresented, onDismiss: {
                if player.pendingFullPlayerPresentation {
                    player.shouldShowFullPlayer = true
                    player.pendingFullPlayerPresentation = false
                }
            }) {
                ProfileMenuView()
                    .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
                    .presentationDragIndicator(Visibility.visible)
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
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            Text(greeting)
                .font(AppTypography.largeTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: AppSpacing.medium)
            Button {
                isProfileMenuPresented = true
            } label: {
                FixedAccountAvatar()
            }
            .buttonStyle(.plain)
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

    private var greeting: String { viewModel.greeting }

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
        case .libraryArtists:
            LibraryArtistsView()
        case .libraryArtist(let name):
            LibraryArtistDetailView(artistName: name)
        }
    }
}

private extension View {
    @ViewBuilder
    func homeScrollChromeTracking(isVisible: Binding<Bool>) -> some View {
        if #available(iOS 18.0, *) {
            onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 72
            } action: { _, shouldShowChrome in
                guard shouldShowChrome != isVisible.wrappedValue else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    isVisible.wrappedValue = shouldShowChrome
                }
            }
        } else {
            self
        }
    }
}

private struct HomeScrollChrome: View {
    @Environment(\.colorScheme) private var colorScheme
    var title: String
    var isVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            let safeTop = max(proxy.safeAreaInsets.top, 54)
            let height = safeTop + 48

            VStack(spacing: 0) {
                chromeBackground
                    .overlay(alignment: .bottom) {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.bottom, 10)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .ignoresSafeArea(edges: .top)
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.18), value: isVisible)
                Spacer(minLength: 0)
            }
        }
        .zIndex(20)
    }

    @ViewBuilder
    private var chromeBackground: some View {
        if colorScheme == .dark {
            Color.black.opacity(0.86)
                .overlay(.ultraThinMaterial.opacity(0.18))
        } else {
            Color(.systemBackground).opacity(0.94)
                .overlay(.regularMaterial.opacity(0.28))
        }
    }
}

private struct FixedAccountAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.accent.opacity(0.95),
                            AppColors.secondaryAccent.opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("MG")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: 38, height: 38)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .accessibilityLabel("Compte")
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
                    ForEach(section.items) { item in
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

enum ProfileDestination: Hashable {
    case auth
    case history
}

struct ProfileMenuView: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.large) {
                    // Header Card
                    profileHeader
                        .padding(.top, AppSpacing.medium)
                    
                    // Sections
                    VStack(spacing: AppSpacing.large) {
                        ProfileSection(title: "Compte") {
                            NavigationLink(value: ProfileDestination.auth) {
                                ProfileRow(icon: "person.crop.circle", title: "Connecter un compte", subtitle: "Compte MusicGlass, profil et préférences", isDisabled: false)
                            }
                            .buttonStyle(.plain)
                            
                            ProfileRow(icon: "gearshape", title: "Préférences du compte", isDisabled: true)
                        }
                        
                        YouTubeMusicProfileSection(authService: container.authService)
                        
                        ProfileSection(title: "Application") {
                            ProfileRow(icon: "music.note", title: "Qualité audio", subtitle: "Élevée (256kbps)", isDisabled: true)
                            ProfileRow(icon: "play.circle", title: "Lecture et confort", isDisabled: true)
                            ProfileRow(icon: "bell", title: "Notifications", isDisabled: true)
                        }
                        
                        ProfileSection(title: "Données") {
                            NavigationLink(value: ProfileDestination.history) {
                                ProfileRow(icon: "clock.arrow.circlepath", title: "Historique d'écoute", isDisabled: false)
                            }
                            .buttonStyle(.plain)
                            
                            ProfileRow(icon: "lock.shield", title: "Confidentialité", isDisabled: true)
                            ProfileRow(icon: "trash", title: "Vider le cache", isDisabled: true)
                        }
                        
                        ProfileSection(title: "À propos") {
                            ProfileRow(icon: "info.circle", title: "Version de l'app", subtitle: "0.0.4 (4)", isDisabled: true)
                        }
                    }
                    .padding(.bottom, AppSpacing.xLarge)
                }
                .padding(.horizontal, AppSpacing.medium)
            }
            .background(Color(.systemGroupedBackground).opacity(0.3).ignoresSafeArea())
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Fermer")
                }
            }
            .navigationDestination(for: ProfileDestination.self) { destination in
                switch destination {
                case .auth:
                    ProfileAuthView()
                case .history:
                    ListeningHistoryView(dismissEntireSheet: { dismiss() })
                }
            }
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: AppSpacing.medium) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.accent.opacity(0.95),
                                AppColors.secondaryAccent.opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("MG")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 90, height: 90)
            .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
            
            VStack(spacing: 4) {
                Text("Invité")
                    .font(.title2.weight(.bold))
                Text("Compte local non connecté")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.large)
        .appGlass(in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct YouTubeMusicProfileSection: View {
    @ObservedObject var authService: AuthService
    @State private var showingLogin = false
    @State private var loginStore: LoginWebViewStore?
    @State private var showingLogoutConfirmation = false
    @AppStorage("musicglass.loginFlowInProgress") private var loginFlowInProgress = false
    
    var body: some View {
        ProfileSection(title: "YouTube Music") {
            if authService.isAuthenticated {
                Button {
                    showingLogoutConfirmation = true
                } label: {
                    HStack(spacing: AppSpacing.medium) {
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("YouTube Music connecté")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("Session active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("Déconnecter")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1), in: Capsule())
                    }
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.medium)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    if loginStore == nil {
                        loginStore = LoginWebViewStore()
                    }
                    loginFlowInProgress = true
                    showingLogin = true
                } label: {
                    ProfileRow(icon: "link", title: "Connecter YouTube Music", subtitle: "Synchronisez playlists, favoris et historique", isDisabled: false)
                }
                .buttonStyle(.plain)
            }
        }
        .alert("Déconnecter YouTube Music ?", isPresented: $showingLogoutConfirmation) {
            Button("Annuler", role: .cancel) {}
            Button("Déconnecter", role: .destructive) {
                Task {
                    await authService.logout()
                }
            }
        } message: {
            Text("Vos playlists synchronisées resteront dans l'app si elles sont déjà chargées, mais la synchronisation YouTube Music sera désactivée jusqu'à une nouvelle connexion.")
        }
        .sheet(isPresented: $showingLogin) {
            NavigationStack {
                if let store = loginStore {
                    LoginWebView(store: store, onLoginSuccess: { cookies, dataSyncId, visitorData in
                        authService.saveAuthData(cookies: cookies, dataSyncId: dataSyncId, visitorData: visitorData)
                        loginFlowInProgress = false
                        loginStore = nil
                    }, isPresented: $showingLogin)
                    .navigationTitle("Connexion YouTube Music")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fermer") {
                                loginFlowInProgress = false
                                showingLogin = false
                                loginStore = nil
                            }
                        }
                    }
                } else {
                    ProgressView()
                        .onAppear {
                            loginStore = LoginWebViewStore()
                        }
                }
            }
        }
        .onAppear {
            if loginFlowInProgress, !authService.isAuthenticated {
                if loginStore == nil { loginStore = LoginWebViewStore() }
                showingLogin = true
            }
        }
    }
}

private struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.medium)
            
            VStack(spacing: 0) {
                content
            }
            .appGlass(in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct ProfileRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var isDisabled: Bool = false
    
    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppColors.accent)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if !isDisabled {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.medium)
        .contentShape(Rectangle())
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

struct ListeningHistoryView: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss
    var dismissEntireSheet: (() -> Void)? = nil
    @State private var tracks: [Track] = []
    @State private var selectedSource: String? = nil // nil = Tout
    @State private var isLoading = false
    @State private var showClearConfirm = false
    @State private var showImportComingSoon = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter
            HStack {
                filterChip(title: "Tout", source: nil)
                filterChip(title: "Dans l'app", source: "inApp")
                filterChip(title: "YouTube Music", source: "youtubeMusic")
                Spacer()
            }
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small)
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(tracks) { track in
                        TrackRow(
                            track: track,
                            isFavorite: false,
                             onPlay: {
                                container.playerEngine.play(track, queue: tracks)
                                container.playerEngine.pendingFullPlayerPresentation = true
                                if let dismissEntireSheet {
                                    dismissEntireSheet()
                                } else {
                                    dismiss()
                                }
                            },
                            onRadio: {
                                container.playerEngine.playRadio(from: track)
                                container.playerEngine.pendingFullPlayerPresentation = true
                                if let dismissEntireSheet {
                                    dismissEntireSheet()
                                } else {
                                    dismiss()
                                }
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(track)
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemGroupedBackground).opacity(0.3).ignoresSafeArea())
        .navigationTitle("Historique d'écoute")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !tracks.isEmpty {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("Vider")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .task {
            loadHistory()
        }
        .alert("Vider l'historique ?", isPresented: $showClearConfirm) {
            Button("Vider", role: .destructive) {
                clearHistory()
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("Cette action supprimera définitivement votre historique d'écoute local.")
        }
        .alert("Import bientôt disponible", isPresented: $showImportComingSoon) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Vous pourrez bientôt importer votre historique YouTube Music via un export Google Takeout.")
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: selectedSource == "youtubeMusic" ? "arrow.down.circle" : "clock")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text(selectedSource == "youtubeMusic" ? "Historique non importé" : "Aucun historique")
                    .font(.title3.weight(.bold))
                
                Text(selectedSource == "youtubeMusic" ? "L'import de l'historique externe nécessite une future mise à jour." : "Les morceaux que vous écoutez apparaîtront ici.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xLarge)
            }
            
            if selectedSource == "youtubeMusic" {
                Button {
                    showImportComingSoon = true
                } label: {
                    Text("En savoir plus sur l'import")
                        .font(.headline)
                        .padding(.horizontal, AppSpacing.large)
                        .padding(.vertical, AppSpacing.medium)
                        .background(AppColors.accent.opacity(0.1), in: Capsule())
                        .foregroundStyle(AppColors.accent)
                }
                .padding(.top, AppSpacing.medium)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func filterChip(title: String, source: String?) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedSource = source
                loadHistory()
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    selectedSource == source ? AppColors.accent : Color.primary.opacity(0.05),
                    in: Capsule()
                )
                .foregroundStyle(selectedSource == source ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
    
    private func loadHistory() {
        isLoading = true
        Task {
            do {
                let fetched = try container.historyRepository.recentlyPlayed(source: selectedSource)
                tracks = fetched
            } catch {
                print("Failed to load history: \(error)")
            }
            isLoading = false
        }
    }
    
    private func delete(_ track: Track) {
        Task {
            try? container.historyRepository.delete(track)
            withAnimation {
                tracks.removeAll { $0.id == track.id }
            }
        }
    }
    
    private func clearHistory() {
        Task {
            try? container.historyRepository.clear()
            withAnimation {
                tracks = []
            }
        }
    }
}

struct ProfileAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authMode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var showComingSoon = false
    
    enum AuthMode {
        case signIn, signUp
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xLarge) {
                // Header
                VStack(spacing: AppSpacing.small) {
                    Text(authMode == .signIn ? "Connexion" : "Créer un compte")
                        .font(.largeTitle.weight(.bold))
                    Text("Retrouvez vos playlists et votre historique sur tous vos appareils.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.large)
                }
                .padding(.top, AppSpacing.large)
                
                // Mode Selector
                Picker("Mode", selection: $authMode) {
                    Text("Connexion").tag(AuthMode.signIn)
                    Text("Inscription").tag(AuthMode.signUp)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppSpacing.medium)
                
                // Form
                VStack(spacing: AppSpacing.medium) {
                    if authMode == .signUp {
                        authField(title: "Nom complet", text: $displayName, icon: "person", contentType: .name)
                    }
                    
                    authField(title: "Adresse e-mail", text: $email, icon: "envelope", contentType: .emailAddress, keyboardType: .emailAddress)
                    
                    authSecureField(title: "Mot de passe", text: $password)
                    
                    if authMode == .signUp {
                        authSecureField(title: "Confirmer le mot de passe", text: $confirmPassword)
                    }
                    
                    if authMode == .signIn {
                        Button("Mot de passe oublié ?") {
                            showComingSoon = true
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppColors.accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(AppSpacing.medium)
                .appGlass(in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, AppSpacing.medium)
                
                // Actions
                VStack(spacing: AppSpacing.medium) {
                    Button {
                        handleAuth()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 8)
                            }
                            Text(authMode == .signIn ? "Se connecter" : "Créer mon compte")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [AppColors.accent, AppColors.secondaryAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .foregroundStyle(.white)
                    }
                    .disabled(isLoading)
                    
                    Text("Ou continuer avec")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        showComingSoon = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.title3)
                            Text("Continuer avec Apple")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.primary, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(Color(.systemBackground))
                    }
                }
                .padding(.horizontal, AppSpacing.medium)
                
                if authMode == .signUp {
                    Text("En créant un compte, vous acceptez nos Conditions d'utilisation et notre Politique de confidentialité.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xLarge)
                }
            }
            .padding(.bottom, AppSpacing.xLarge)
        }
        .background(Color(.systemGroupedBackground).opacity(0.3).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert("Bientôt disponible", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Le système d'authentification sera activé dans une prochaine mise à jour.")
        }
    }
    
    private func authField(title: String, text: Binding<String>, icon: String, contentType: UITextContentType? = nil, keyboardType: UIKeyboardType = .default) -> some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            TextField(title, text: text)
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding()
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func authSecureField(title: String, text: Binding<String>) -> some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: "lock")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            SecureField(title, text: text)
                .textContentType(authMode == .signIn ? .password : .newPassword)
        }
        .padding()
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func handleAuth() {
        // Validation basique
        if email.isEmpty || password.isEmpty { return }
        
        isLoading = true
        // Simulation d'appel réseau
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isLoading = false
            showComingSoon = true
        }
    }
}
