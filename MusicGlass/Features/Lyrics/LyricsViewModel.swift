import Foundation

@MainActor
final class LyricsViewModel: ObservableObject {
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: YouTubeMusicClientProtocol
    let track: Track

    init(client: YouTubeMusicClientProtocol, track: Track) {
        self.client = client
        self.track = track
    }

    func load() {
        guard lyrics == nil else { return }
        isLoading = true
        Task {
            do {
                lyrics = try await client.getLyrics(videoId: track.videoId, metadata: track)
                if lyrics == nil {
                    errorMessage = AppError.lyricsUnavailable.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
