import Foundation

@MainActor
final class AlbumDetailViewModel: ObservableObject {
    @Published private(set) var album: Album?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingArtwork = false
    @Published var errorMessage: String?

    private let client: YouTubeMusicClientProtocol
    private let browseId: String

    init(client: YouTubeMusicClientProtocol, browseId: String) {
        self.client = client
        self.browseId = browseId
    }

    func load() {
        guard album == nil else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let loadedAlbum = try await client.getAlbum(browseId: browseId)
                album = loadedAlbum
                isLoading = false
                await refreshArtwork(for: loadedAlbum)
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func refreshArtwork(for loadedAlbum: Album) async {
        guard !loadedAlbum.tracks.isEmpty else { return }
        isRefreshingArtwork = true

        let visibleTracks = await client.enrichArtwork(for: loadedAlbum.tracks, fallbackAlbum: loadedAlbum, limit: 18)
        updateTracks(visibleTracks, for: loadedAlbum.id)

        let allTracks = await client.enrichArtwork(for: visibleTracks, fallbackAlbum: loadedAlbum, limit: 80)
        updateTracks(allTracks, for: loadedAlbum.id)

        isRefreshingArtwork = false
    }

    private func updateTracks(_ tracks: [Track], for albumId: String) {
        guard var current = album, current.id == albumId else { return }
        current.tracks = tracks
        album = current
    }
}

@MainActor
final class ArtistDetailViewModel: ObservableObject {
    @Published private(set) var page: ArtistPage?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: YouTubeMusicClientProtocol
    private let browseId: String

    init(client: YouTubeMusicClientProtocol, browseId: String) {
        self.client = client
        self.browseId = browseId
    }

    func load() {
        guard page == nil else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                page = try await client.getArtist(browseId: browseId)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

@MainActor
final class PlaylistDetailViewModel: ObservableObject {
    @Published private(set) var playlist: Playlist?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshingArtwork = false
    @Published var errorMessage: String?

    private let client: YouTubeMusicClientProtocol
    private let browseId: String

    init(client: YouTubeMusicClientProtocol, browseId: String) {
        self.client = client
        self.browseId = browseId
    }

    func load() {
        guard playlist == nil else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let loadedPlaylist = try await client.getPlaylist(browseId: browseId)
                playlist = loadedPlaylist
                isLoading = false
                await refreshArtwork(for: loadedPlaylist)
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func refreshArtwork(for loadedPlaylist: Playlist) async {
        guard !loadedPlaylist.tracks.isEmpty else { return }
        isRefreshingArtwork = true

        let visibleTracks = await client.enrichArtwork(for: loadedPlaylist.tracks, fallbackAlbum: nil, limit: 18)
        updateTracks(visibleTracks, for: loadedPlaylist.id)

        let allTracks = await client.enrichArtwork(for: visibleTracks, fallbackAlbum: nil, limit: 80)
        updateTracks(allTracks, for: loadedPlaylist.id)

        isRefreshingArtwork = false
    }

    private func updateTracks(_ tracks: [Track], for playlistId: String) {
        guard var current = playlist, current.id == playlistId else { return }
        current.tracks = tracks
        current.trackCount = tracks.count
        playlist = current
    }
}
