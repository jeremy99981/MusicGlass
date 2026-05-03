import SwiftUI

struct QueueScreen: View {
    @EnvironmentObject private var player: AVPlayerEngine

    var body: some View {
        NavigationStack {
            List {
                if let current = player.currentTrack {
                    Section("Lecture en cours") {
                        TrackRow(track: current) {}
                    }
                }
                Section("File d’attente") {
                    if upcomingTracks.isEmpty {
                        Text("La file d’attente est vide.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(upcomingTracks) { track in
                            TrackRow(track: track) {
                                player.play(track, queue: player.queue.tracks)
                            }
                        }
                        .onDelete(perform: player.removeUpcomingQueueItems)
                        .onMove(perform: player.moveUpcomingQueueItems)
                    }
                }
            }
            .navigationTitle("File d’attente")
            .toolbar { EditButton() }
        }
    }

    private var upcomingTracks: [Track] {
        guard let current = player.currentTrack else {
            return player.queue.upcomingTracks
        }
        return player.queue.upcomingTracks.filter { !$0.isSameQueueItem(as: current) }
    }
}

private extension Track {
    func isSameQueueItem(as other: Track) -> Bool {
        if videoId == other.videoId || id == other.id {
            return true
        }
        let lhsTitle = title.queueScreenNormalized
        let rhsTitle = other.title.queueScreenNormalized
        let lhsArtist = artistLine.queueScreenNormalized
        let rhsArtist = other.artistLine.queueScreenNormalized
        return !lhsTitle.isEmpty && !lhsArtist.isEmpty && lhsTitle == rhsTitle && lhsArtist == rhsArtist
    }
}

private extension String {
    var queueScreenNormalized: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
