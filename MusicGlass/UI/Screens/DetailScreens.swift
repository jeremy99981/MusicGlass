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
                LazyVStack(alignment: .leading, spacing: AppSpacing.large) {
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

struct LibraryArtistsView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AVPlayerEngine
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var artists: [LibraryArtist] = []
    @State private var topArtists: [ArtistListeningRank] = []
    @State private var isLoading = true

    var body: some View {
        ZStack(alignment: .top) {
            background
            
            VStack(spacing: 0) {
                customHeader
                
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredArtists.isEmpty {
                    emptyState
                } else {
                    artistList
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            loadArtists()
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color.orange.opacity(0.05),
                Color.purple.opacity(0.03)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var customHeader: some View {
        VStack(spacing: AppSpacing.medium) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                
                Text("Artistes")
                    .font(AppTypography.title)
                    .padding(.leading, 8)
                
                Spacer()
                
                Text("\(artists.count)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, AppSpacing.medium)
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Rechercher un artiste", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, AppSpacing.medium)
        }
        .padding(.top, 12)
        .padding(.bottom, AppSpacing.medium)
    }

    private var artistList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.small) {
                if searchText.isEmpty && !topArtists.isEmpty {
                    podiumSection
                        .padding(.bottom, AppSpacing.medium)
                    
                    if !filteredRemainingArtists.isEmpty {
                        HStack {
                            Text("Autres artistes")
                                .font(AppTypography.sectionTitle)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.vertical, AppSpacing.small)
                    }
                }
                
                ForEach(filteredRemainingArtists) { artist in
                    artistRow(artist)
                }
            }
            .padding(.horizontal, AppSpacing.medium)
            .padding(.bottom, 140)
        }
    }
    
    private var filteredRemainingArtists: [LibraryArtist] {
        if searchText.isEmpty {
            let topIds = Set(topArtists.map(\.id))
            return artists.filter { !topIds.contains($0.id) }
        }
        return artists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var podiumSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("Top artistes")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(.primary)
            
            HStack(alignment: .bottom, spacing: AppSpacing.small) {
                if topArtists.count > 1 {
                    podiumItem(for: topArtists[1], isCenter: false)
                } else {
                    Spacer().frame(maxWidth: .infinity)
                }
                
                if let first = topArtists.first {
                    podiumItem(for: first, isCenter: true)
                }
                
                if topArtists.count > 2 {
                    podiumItem(for: topArtists[2], isCenter: false)
                } else {
                    Spacer().frame(maxWidth: .infinity)
                }
            }
            .padding(AppSpacing.medium)
            .appGlass(in: RoundedRectangle(cornerRadius: 24))
        }
    }
    
    private func podiumItem(for rank: ArtistListeningRank, isCenter: Bool) -> some View {
        NavigationLink(value: MusicDestination.libraryArtist(rank.relatedArtist.name)) {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    ArtworkView(
                        url: rank.relatedArtist.bestThumbnailURL, 
                        size: isCenter ? 90 : 70, 
                        cornerRadius: isCenter ? 45 : 35
                    )
                    
                    Text("\(rank.rank)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(rank.rank == 1 ? Color.yellow : (rank.rank == 2 ? Color.gray : Color.orange))
                        )
                        .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 1))
                        .offset(x: 4, y: 4)
                }
                
                VStack(spacing: 2) {
                    Text(rank.relatedArtist.name)
                        .font(isCenter ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text("\(rank.playCount) écoute\(rank.playCount > 1 ? "s" : "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func artistRow(_ artist: LibraryArtist) -> some View {
        NavigationLink(value: MusicDestination.libraryArtist(artist.name)) {
            HStack(spacing: AppSpacing.medium) {
                ArtworkView(url: artist.bestThumbnailURL, size: 60, cornerRadius: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(artist.trackCount) titre\(artist.trackCount > 1 ? "s" : "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(AppSpacing.small)
            .appGlass(in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: "person.2.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.3))
            Text(searchText.isEmpty ? "Aucun artiste" : "Aucun résultat pour \"\(searchText)\"")
                .font(.headline)
            Text(searchText.isEmpty ? "Ajoutez des titres à vos favoris ou à vos playlists pour les voir ici." : "Essayez une autre recherche.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredArtists: [LibraryArtist] {
        if searchText.isEmpty {
            return artists
        }
        return artists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func loadArtists() {
        let favRepo = container.favoritesRepository
        let histRepo = container.historyRepository
        let playRepo = container.playlistRepository
        let client = container.youTubeMusicClient
        let auth = container.authService
        
        Task {
            let libraryVM = LibraryViewModel(
                favoritesRepository: favRepo,
                historyRepository: histRepo,
                playlistRepository: playRepo,
                youTubeMusicClient: client,
                authService: auth
            )
            libraryVM.load()
            
            let allTracks = (libraryVM.allFavorites + libraryVM.allHistory).uniqueById()
            
            var artistGroups: [String: [Track]] = [:] // Key: normalized name
            var artistDisplayNames: [String: String] = [:] // Key: normalized -> best display name
            var artistBrowseIds: [String: String] = [:]
            
            for track in allTracks {
                for artist in track.artists {
                    let rawName = artist.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !rawName.isEmpty else { continue }
                    
                    let key = rawName.lowercased()
                    artistGroups[key, default: []].append(track)
                    
                    // On garde le nom le plus "riche" (celui qui a des majuscules si possible)
                    if artistDisplayNames[key] == nil || (rawName != key && artistDisplayNames[key] == key) {
                        artistDisplayNames[key] = rawName
                    }
                    
                    if let bid = artist.browseId {
                        artistBrowseIds[key] = bid
                    }
                }
            }
            
            let mappedArtists: [LibraryArtist] = artistGroups.compactMap { key, tracks in
                guard let name = artistDisplayNames[key], !name.isEmpty else { return nil }
                let liked = tracks.filter { $0.isLiked }
                return LibraryArtist(name: name, tracks: tracks, likedTracks: liked, playlists: [], browseId: artistBrowseIds[key])
            }
            
            let sortedArtists = mappedArtists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            
            // Calcul du podium
            let historyRecords = (try? histRepo.allHistoryRecords()) ?? []
            var artistPlayCounts: [String: Int] = [:]
            var artistUniqueTracks: [String: Set<String>] = [:]
            var artistLastPlayed: [String: Date] = [:]
            
            for record in historyRecords {
                let track = record.toTrack()
                for artist in track.artists {
                    let rawName = artist.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !rawName.isEmpty else { continue }
                    let key = rawName.lowercased()
                    
                    artistPlayCounts[key, default: 0] += record.playCount
                    artistUniqueTracks[key, default: []].insert(record.trackId)
                    
                    if let currentLast = artistLastPlayed[key] {
                        if record.updatedAt > currentLast {
                            artistLastPlayed[key] = record.updatedAt
                        }
                    } else {
                        artistLastPlayed[key] = record.updatedAt
                    }
                }
            }
            
            let sortedKeys = artistPlayCounts.keys.sorted { key1, key2 in
                let count1 = artistPlayCounts[key1] ?? 0
                let count2 = artistPlayCounts[key2] ?? 0
                if count1 != count2 { return count1 > count2 }
                
                let unique1 = artistUniqueTracks[key1]?.count ?? 0
                let unique2 = artistUniqueTracks[key2]?.count ?? 0
                if unique1 != unique2 { return unique1 > unique2 }
                
                let date1 = artistLastPlayed[key1] ?? .distantPast
                let date2 = artistLastPlayed[key2] ?? .distantPast
                if date1 != date2 { return date1 > date2 }
                
                return key1 < key2
            }
            
            var topRanks: [ArtistListeningRank] = []
            var currentRank = 1
            for key in sortedKeys {
                if currentRank > 3 { break }
                if (artistPlayCounts[key] ?? 0) <= 0 { continue }
                
                if let related = sortedArtists.first(where: { $0.id == key }) {
                    topRanks.append(ArtistListeningRank(
                        id: key,
                        rank: currentRank,
                        playCount: artistPlayCounts[key] ?? 0,
                        uniqueTrackCount: artistUniqueTracks[key]?.count ?? 0,
                        relatedArtist: related
                    ))
                    currentRank += 1
                }
            }
            
            await MainActor.run {
                self.artists = sortedArtists
                self.topArtists = topRanks
                self.isLoading = false
            }
        }
    }
}

struct ArtistListeningRank: Identifiable, Hashable {
    let id: String
    let rank: Int
    let playCount: Int
    let uniqueTrackCount: Int
    let relatedArtist: LibraryArtist
}

struct LibraryArtist: Identifiable, Hashable {
    let name: String
    let tracks: [Track]
    let likedTracks: [Track]
    let playlists: [Playlist]
    let browseId: String?
    
    var id: String { name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
    var trackCount: Int { 
        Set(tracks.map(\.id)).count
    }
    
    var bestThumbnailURL: URL? {
        if let artistThumb = tracks.first(where: { $0.artists.contains(where: { $0.name == name && $0.bestThumbnailURL != nil }) })?
            .artists.first(where: { $0.name == name })?.bestThumbnailURL {
            return artistThumb
        }
        return tracks.first?.bestThumbnailURL
    }
}

struct LibraryArtistDetailView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: AVPlayerEngine
    @Environment(\.dismiss) private var dismiss
    
    let artistName: String
    @State private var artist: LibraryArtist?
    @State private var isLoading = true
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let artist {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                        header(artist)
                        actions(artist)
                        
                        if !artist.likedTracks.isEmpty {
                            TrackList(title: "Titres aimés", tracks: artist.likedTracks, onRadio: { player.playRadio(from: $0) }) { track in
                                player.play(track, queue: artist.likedTracks)
                            }
                        }
                        
                        TrackList(title: "Tous les titres", tracks: artist.tracks, onRadio: { player.playRadio(from: $0) }) { track in
                            player.play(track, queue: artist.tracks)
                        }
                        
                        if !artist.playlists.isEmpty {
                            playlistsSection(artist)
                        }
                    }
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
            } else {
                Text("Artiste introuvable")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            loadArtist()
        }
    }
    
    private func header(_ artist: LibraryArtist) -> some View {
        VStack(spacing: AppSpacing.medium) {
            ArtworkView(url: artist.bestThumbnailURL, size: 200, cornerRadius: 100)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            
            VStack(spacing: 4) {
                Text(artist.name)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                
                Text("\(artist.trackCount) titres • \(artist.playlists.count) playlists")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
    
    private func actions(_ artist: LibraryArtist) -> some View {
        HStack(spacing: AppSpacing.medium) {
            Button {
                if let first = artist.tracks.first {
                    player.play(first, queue: artist.tracks)
                }
            } label: {
                Label("Lire", systemImage: AppIcons.play)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Button {
                let shuffled = artist.tracks.shuffled()
                if let first = shuffled.first {
                    player.play(first, queue: shuffled)
                }
            } label: {
                Label("Mélanger", systemImage: AppIcons.shuffle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.horizontal, AppSpacing.medium)
    }
    
    private func playlistsSection(_ artist: LibraryArtist) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("Apparaît dans")
                .font(AppTypography.sectionTitle)
                .padding(.horizontal, AppSpacing.medium)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.medium) {
                    ForEach(artist.playlists) { playlist in
                        NavigationLink(value: MusicDestination.playlist(playlist.browseId ?? playlist.id)) {
                            VStack(alignment: .leading, spacing: 8) {
                                ArtworkView(url: playlist.bestThumbnailURL, size: 140, cornerRadius: 16)
                                Text(playlist.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .frame(width: 140, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppSpacing.medium)
            }
        }
    }
    
    private func loadArtist() {
        let favRepo = container.favoritesRepository
        let histRepo = container.historyRepository
        let playRepo = container.playlistRepository
        let client = container.youTubeMusicClient
        let auth = container.authService
        
        Task {
            let libraryVM = LibraryViewModel(
                favoritesRepository: favRepo,
                historyRepository: histRepo,
                playlistRepository: playRepo,
                youTubeMusicClient: client,
                authService: auth
            )
            libraryVM.load()
            
            // Wait for YT data if needed
            if auth.isAuthenticated {
                // To avoid waiting indefinitely, we take what's loaded or wait a bit
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            let allTracks = (libraryVM.allFavorites + libraryVM.allHistory).uniqueById()
            let allPlaylists = libraryVM.ytPlaylists
            
            let artistTracks = allTracks.filter { track in
                track.artists.contains { $0.name.lowercased() == artistName.lowercased() }
            }
            
            let likedTracks = libraryVM.allFavorites.filter { track in
                track.artists.contains { $0.name.lowercased() == artistName.lowercased() }
            }
            
            let artistPlaylists = allPlaylists.filter { playlist in
                playlist.tracks.contains { track in
                    track.artists.contains { $0.name.lowercased() == artistName.lowercased() }
                }
            }
            
            let browseId = artistTracks.first?.artists.first(where: { $0.name.lowercased() == artistName.lowercased() })?.browseId
            
            await MainActor.run {
                self.artist = LibraryArtist(
                    name: artistName,
                    tracks: artistTracks,
                    likedTracks: likedTracks,
                    playlists: artistPlaylists,
                    browseId: browseId
                )
                self.isLoading = false
            }
        }
    }
}

extension Array where Element: Identifiable {
    func uniqueById() -> [Element] {
        var seen = Set<Element.ID>()
        return filter { seen.insert($0.id).inserted }
    }
}
