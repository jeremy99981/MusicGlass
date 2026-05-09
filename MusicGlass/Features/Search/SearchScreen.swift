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
                if pendingFullPlayer {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000) // Attendre que le sheet soit disparu
                        player.shouldShowFullPlayer = true
                        pendingFullPlayer = false
                    }
                }
            }) {
                AIAssistantModalView(container: container) { shouldOpenPlayer in
                    pendingFullPlayer = shouldOpenPlayer
                    showAISearch = false
                }
                .environmentObject(container)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
            }
        }
    }
    
    @State private var showAISearch = false
    @State private var pendingFullPlayer = false

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
    @StateObject private var viewModel: AIAssistantViewModel
    var onFinish: ((Bool) -> Void)?
    
    init(container: AppContainer, onFinish: ((Bool) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: AIAssistantViewModel(container: container))
        self.onFinish = onFinish
    }
    
    var body: some View {
        VStack(spacing: 30) {
            header
            Spacer()
            mainContent
            Spacer()
        }
        .padding(30)
        .appGlass(in: RoundedRectangle(cornerRadius: 32))
        .onDisappear { viewModel.reset() }
    }
    
    private var header: some View {
        HStack {
            Text("Assistant IA").font(.title2.bold())
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .padding(10)
                    .appGlass(in: Circle(), interactive: true)
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.state {
        case .idle:
            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundStyle(AppColors.accent.gradient)
                Text("Comment puis-je vous aider ?")
                    .font(.headline)
                Button("Démarrer l'Assistant") {
                    Task { await viewModel.startAssistant() }
                }
                .appGlass(in: Capsule(), interactive: true)
                
                Button("Écrire ma demande") {
                    viewModel.setState(.textInput(nil), reason: "User chose text input")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            
        case .checkingPermissions, .requestingSpeechPermission, .requestingMicrophonePermission:
            InitializingView(text: "Vérification des autorisations...")
            
        case .startingAudio:
            InitializingView(text: "Préparation du micro...")
            
        case .listening:
            VStack(spacing: 20) {
                WaveformView()
                    .frame(height: 80)
                    .padding(.vertical)
                Text(viewModel.transcript.isEmpty ? "Je vous écoute..." : viewModel.transcript)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                HStack(spacing: 20) {
                    Button("Annuler") { viewModel.reset() }
                        .appGlass(in: Capsule(), interactive: true)
                    Button("Terminer") {
                        Task { await viewModel.finishListening() }
                    }
                    .appGlass(tint: AppColors.accent, in: Capsule(), interactive: true)
                }
            }
            
        case .processingSpeech, .thinking:
            InitializingView(text: "Analyse de votre demande...")
            
        case .resolving:
            InitializingView(text: "Recherche de la musique...")
            
        case .showingAlbumChoices(let question, let albums):
            VStack(spacing: 20) {
                Text(question)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(albums) { album in
                            Button {
                                Task { await viewModel.selectAlbum(album) }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    AsyncImage(url: album.bestThumbnailURL) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Color.gray.opacity(0.3)
                                    }
                                    .frame(width: 140, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    
                                    Text(album.title)
                                        .font(.subheadline.bold())
                                        .lineLimit(2)
                                    
                                    Text(album.artists.first?.name ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 140)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                
                Button("Annuler") { viewModel.reset() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
        case .playing:
            VStack(spacing: 20) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(AppColors.accent.gradient)
                Text("Lecture en cours...")
                    .font(.headline)
            }
            .onAppear {
                Task {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    onFinish?(true)
                }
            }
            
        case .textInput(let message):
            VStack(spacing: 20) {
                if let message = message {
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                TextField("Artiste, album, humeur...", text: $viewModel.textInput)
                    .padding()
                    .appGlass(in: RoundedRectangle(cornerRadius: 16))
                
                Button("Envoyer") {
                    Task { await viewModel.processText(viewModel.textInput) }
                }
                .disabled(viewModel.textInput.isEmpty)
                .appGlass(tint: viewModel.textInput.isEmpty ? nil : AppColors.accent, in: Capsule(), interactive: true)
                
                Button("Réessayer le micro") {
                    viewModel.reset()
                    Task { await viewModel.startAssistant() }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top)
            }
            
        case .error(let msg):
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.orange)
                Text(msg)
                    .multilineTextAlignment(.center)
                Button("Réessayer") { viewModel.reset() }
                    .appGlass(in: Capsule(), interactive: true)
            }
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
        // Initialisation sécurisée du recognizer
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
        // Arrêt propre de toute session précédente
        stopListening()
        
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
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        // SÉCURITÉ : Accès au nœud d'entrée peut crasher si non autorisé
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw NSError(domain: "SpeechVoiceService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Configuration micro invalide"])
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
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
        // SÉCURITÉ : Vérifier si l'engine tourne pour éviter des appels inutiles
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
            setState(.error("Impossible de démarrer l'écoute. Vérifiez votre micro ou réessayez."), reason: "Start error: \(error)")
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
        case .openSearch(let q):
            setState(.error("Action non supportée pour l'instant: recherche \(q)"), reason: "Search resolution")
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
