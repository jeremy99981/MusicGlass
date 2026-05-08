import SwiftUI

struct MiniPlayer: View {
    var namespace: Namespace.ID
    var openFullPlayer: () -> Void

    var body: some View {
        MiniPlayerBody(namespace: namespace, layout: .expanded, openFullPlayer: openFullPlayer)
    }
}

@available(iOS 26.0, *)
struct TabBarMiniPlayerAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var namespace: Namespace.ID
    var openFullPlayer: () -> Void

    var body: some View {
        MiniPlayerBody(
            namespace: namespace,
            layout: placement == .inline ? .inline : .expanded,
            openFullPlayer: openFullPlayer
        )
    }
}

private struct MiniPlayerBody: View {
    @EnvironmentObject private var player: AVPlayerEngine
    @Environment(\.colorScheme) private var colorScheme
    var namespace: Namespace.ID
    var layout: MiniPlayerLayout
    var openFullPlayer: () -> Void

    var body: some View {
        HStack(spacing: layout.spacing) {
            Button(action: openFullPlayer) {
                HStack(spacing: layout.contentSpacing) {
                    ArtworkView(
                        url: player.currentTrack?.bestThumbnailURL,
                        size: layout.artworkSize,
                        cornerRadius: layout.artworkCornerRadius
                    )
                    .matchedGeometryEffect(id: "player-artwork", in: namespace)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.currentTrack?.title ?? "Aucun titre")
                            .font(layout.titleFont)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(layout.subtitleFont)
                            .foregroundStyle(player.errorMessage == nil ? Color.secondary : Color.red)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(nil, value: layout)

                    Spacer(minLength: AppSpacing.small)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: showsPauseIcon ? AppIcons.pause : AppIcons.play)
                    .font(layout.controlFont)
                    .frame(width: layout.controlSize, height: layout.controlSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsPauseIcon ? "Pause" : "Lecture")
        }
        .padding(.leading, layout.leadingPadding)
        .padding(.trailing, layout.trailingPadding)
        .padding(.vertical, layout.verticalPadding)
        .background {
            Capsule()
                .fill(colorScheme == .light ? Color.white.opacity(0.14) : Color.clear)
        }
        .appGlass(tint: AppColors.accent.opacity(layout.glassTintOpacity), in: Capsule(), interactive: true)
        .id("mini-player-glass-\(colorScheme == .dark ? "dark" : "light")")
        .environment(\.colorScheme, colorScheme)
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

private enum MiniPlayerLayout: Hashable {
    case expanded
    case inline

    var artworkSize: CGFloat {
        switch self {
        case .expanded: 42
        case .inline: 34
        }
    }

    var artworkCornerRadius: CGFloat {
        switch self {
        case .expanded: AppRadius.small
        case .inline: 7
        }
    }

    var spacing: CGFloat {
        switch self {
        case .expanded: AppSpacing.medium
        case .inline: AppSpacing.small
        }
    }

    var contentSpacing: CGFloat {
        switch self {
        case .expanded: AppSpacing.medium
        case .inline: AppSpacing.small
        }
    }

    var controlSize: CGFloat {
        switch self {
        case .expanded: 44
        case .inline: 34
        }
    }

    var leadingPadding: CGFloat {
        switch self {
        case .expanded: 8
        case .inline: 6
        }
    }

    var trailingPadding: CGFloat {
        switch self {
        case .expanded: 6
        case .inline: 4
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .expanded: 7
        case .inline: 5
        }
    }

    var glassTintOpacity: Double {
        switch self {
        case .expanded: 0.10
        case .inline: 0.08
        }
    }

    var titleFont: Font {
        switch self {
        case .expanded: .subheadline.weight(.semibold)
        case .inline: .caption.weight(.semibold)
        }
    }

    var subtitleFont: Font {
        switch self {
        case .expanded: .caption
        case .inline: .caption2
        }
    }

    var controlFont: Font {
        switch self {
        case .expanded: .headline
        case .inline: .subheadline.weight(.semibold)
        }
    }
}
