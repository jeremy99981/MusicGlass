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
                    if player.queue.tracks.isEmpty {
                        Text("La file d’attente est vide.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(player.queue.tracks) { track in
                            TrackRow(track: track) {
                                player.play(track, queue: player.queue.tracks)
                            }
                        }
                        .onDelete(perform: player.removeFromQueue)
                        .onMove(perform: player.moveQueueItems)
                    }
                }
            }
            .navigationTitle("File d’attente")
            .toolbar { EditButton() }
        }
    }
}
