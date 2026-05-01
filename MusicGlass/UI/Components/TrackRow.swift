import SwiftUI

struct TrackRow: View {
    var track: Track
    var isFavorite: Bool = false
    var animateArtworkUpdates = false
    var onPlay: () -> Void
    var onRadio: (() -> Void)?
    var onFavorite: (() -> Void)?

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: AppSpacing.medium) {
                ArtworkView(url: track.bestThumbnailURL, size: 52, cornerRadius: AppRadius.small, animateArtworkUpdates: animateArtworkUpdates)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(track.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if track.explicit {
                            Text("E")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .background(.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                            }
                    }
                    if !track.artistLine.isEmpty {
                        Text(track.artistLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: AppSpacing.small)
                if let duration = track.duration {
                    Text(duration.musicTimeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Menu {
                    if let onFavorite {
                        Button(action: onFavorite) {
                            Label(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: isFavorite ? AppIcons.heartFill : AppIcons.heart)
                        }
                    }
                    Button(action: onPlay) {
                        Label("Lecture", systemImage: AppIcons.play)
                    }
                    if let onRadio {
                        Button(action: onRadio) {
                            Label("Lancer la radio", systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                } label: {
                    Image(systemName: AppIcons.more)
                        .font(.headline)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(track.artistLine.isEmpty ? track.title : "\(track.title), \(track.artistLine)")
    }
}

#Preview {
    TrackRow(track: .preview) {}
        .padding()
}
