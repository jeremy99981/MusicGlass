import SwiftUI

struct MiniPlayer: View {
    @EnvironmentObject private var player: AVPlayerEngine
    var namespace: Namespace.ID
    var openFullPlayer: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Button(action: openFullPlayer) {
                HStack(spacing: AppSpacing.medium) {
                    ArtworkView(url: player.currentTrack?.bestThumbnailURL, size: 42, cornerRadius: AppRadius.small)
                        .matchedGeometryEffect(id: "player-artwork", in: namespace)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.currentTrack?.title ?? "Aucun titre")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(player.errorMessage == nil ? Color.secondary : Color.red)
                            .lineLimit(1)
                    }
                    Spacer(minLength: AppSpacing.small)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: showsPauseIcon ? AppIcons.pause : AppIcons.play)
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsPauseIcon ? "Pause" : "Lecture")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .appGlass(tint: AppColors.accent.opacity(0.10), in: Capsule(), interactive: true)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    if value.translation.width < -40 {
                        player.next()
                    } else if value.translation.width > 40 {
                        player.previous()
                    }
                }
        )
    }

    private var subtitle: String {
        if let error = player.errorMessage, !error.isEmpty {
            return error
        }
        return player.currentTrack?.artistLine ?? ""
    }

    private var showsPauseIcon: Bool {
        switch player.state {
        case .playing, .buffering:
            return true
        case .idle, .loading, .paused, .failed:
            return false
        }
    }
}
