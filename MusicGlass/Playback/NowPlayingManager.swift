import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingManager {
    private var artworkTask: Task<Void, Never>?
    private var currentArtworkTrackId: String?

    func update(track: Track?, state: PlayerState, elapsed: TimeInterval, duration: TimeInterval?) {
        guard let track else {
            artworkTask?.cancel()
            currentArtworkTrackId = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistLine,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0
        ]
        if let album = track.album?.title {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let duration = duration ?? track.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = existing
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if currentArtworkTrackId != track.id {
            updateArtwork(for: track)
        }
    }

    func clear() {
        artworkTask?.cancel()
        currentArtworkTrackId = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func updateArtwork(for track: Track) {
        artworkTask?.cancel()
        currentArtworkTrackId = track.id
        guard let url = track.bestThumbnailURL else { return }
        artworkTask = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, let image = UIImage(data: data) else { return }
                let artwork = Self.makeArtwork(data: data, boundsSize: image.size)
                await MainActor.run {
                    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    info[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            } catch {
                AppLogger.playback.debug("Artwork load failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated private static func makeArtwork(data: Data, boundsSize: CGSize) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: boundsSize) { _ in
            UIImage(data: data) ?? UIImage()
        }
    }
}
