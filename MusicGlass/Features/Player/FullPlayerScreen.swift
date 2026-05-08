import SwiftUI
import UIKit

struct FullPlayerScreen: View {
    @EnvironmentObject private var player: AVPlayerEngine
    @State private var dismissDragOffset: CGFloat = 0
    @State private var dismissAxis: ArtworkSwipeAxis?
    @State private var isDismissing = false

    var namespace: Namespace.ID
    var dismiss: () -> Void
    var showQueue: () -> Void
    var showLyrics: (Track) -> Void
    var openArtist: (Artist) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let windowInsets = UIApplication.musicGlassSafeAreaInsets
            let safeTop = max(proxy.safeAreaInsets.top, windowInsets.top)
            let safeBottom = max(proxy.safeAreaInsets.bottom, windowInsets.bottom)
            let isCompact = size.height < 850
            let horizontalPadding: CGFloat = size.width < 390 ? 28 : 34
            let contentWidth = max(size.width - (horizontalPadding * 2), 260)
            let artworkSize = min(contentWidth, size.height * (isCompact ? 0.42 : 0.43), 354)
            let contentHeight = size.height

            ZStack(alignment: .top) {
                playerBackground(size: size)

                VStack(spacing: 0) {
                    closeHandle(safeTop: safeTop)

                    SwipeablePlayerArtworkView(
                        url: player.currentTrack?.bestThumbnailURL,
                        previousURL: previousSwipeArtworkURL,
                        nextURL: nextSwipeArtworkURL,
                        size: artworkSize,
                        identity: player.currentTrack?.id,
                        previousRestartsCurrentTrack: PlayerProgressTracker.shared.progress > 5,
                        onPrevious: { player.previous() },
                        onNext: { player.next() }
                    )
                        .padding(.top, isCompact ? 6 : 12)

                    VStack(alignment: .leading, spacing: isCompact ? 14 : 18) {
                        metadataRow

                        PlayerProgressSection(player: player)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, isCompact ? 16 : 20)

                    Spacer(minLength: isCompact ? 18 : 24)

                    transportControls

                    Spacer(minLength: isCompact ? 18 : 24)

                    volumeControl

                    Spacer(minLength: isCompact ? 16 : 22)

                    bottomUtilities
                }
                .padding(.bottom, max(safeBottom + 12, 28))
                .frame(width: contentWidth, height: contentHeight, alignment: .top)
                .animation(nil, value: player.state)
                .zIndex(10)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
            .ignoresSafeArea()
            .offset(y: max(dismissDragOffset, 0))
            .simultaneousGesture(dismissDragGesture(screenHeight: size.height), including: .all)
        }
        .ignoresSafeArea()
        .presentationBackground(.clear)
        .background(ClearFullScreenCoverBackground())
        .preferredColorScheme(.dark)
    }

    private func dismissDragGesture(screenHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard !isDismissing else { return }
                let translation = value.translation
                updateDismissAxis(for: translation)

                guard dismissAxis == .vertical, translation.height > 0 else {
                    if dismissAxis == .horizontal, dismissDragOffset != 0 {
                        setDismissOffset(0)
                    }
                    return
                }

                setDismissOffset(translation.height)
            }
            .onEnded { value in
                guard !isDismissing else { return }
                let translation = value.translation
                let predicted = value.predictedEndTranslation
                let isVerticalDismiss = dismissAxis == .vertical ||
                    (translation.height > 0 && abs(translation.height) > abs(translation.width) * 0.72)
                dismissAxis = nil
                guard isVerticalDismiss else {
                    settleDismissOffsetBackToTop()
                    return
                }

                if translation.height > 110 || predicted.height > 190 {
                    finishDismiss(from: max(translation.height, dismissDragOffset), screenHeight: screenHeight)
                } else {
                    settleDismissOffsetBackToTop()
                }
            }
    }

    private func updateDismissAxis(for translation: CGSize) {
        guard dismissAxis == nil else { return }
        let absX = abs(translation.width)
        let absY = abs(translation.height)
        guard absX > 8 || absY > 8 else { return }

        if absX > absY * 1.25 {
            dismissAxis = .horizontal
        } else if translation.height > 0, absY > absX * 0.72 {
            dismissAxis = .vertical
        }
    }

    private func setDismissOffset(_ offset: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dismissDragOffset = max(offset, 0)
        }
    }

    private func settleDismissOffsetBackToTop() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            dismissDragOffset = 0
        }
    }

    private func finishDismiss(from currentOffset: CGFloat, screenHeight: CGFloat) {
        let targetOffset = screenHeight + 80
        setDismissOffset(currentOffset)
        isDismissing = true

        withAnimation(.easeOut(duration: 0.22)) {
            dismissDragOffset = targetOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            dismiss()
        }
    }

    private func playerBackground(size: CGSize) -> some View {
        ZStack {
            Color(red: 0.10, green: 0.15, blue: 0.15)

            AsyncImage(url: player.currentTrack?.bestThumbnailURL) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 76)
                        .scaleEffect(1.34)
                        .saturation(1.18)
                        .opacity(0.52)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color(red: 0.31, green: 0.39, blue: 0.38).opacity(0.64),
                    Color(red: 0.13, green: 0.22, blue: 0.22).opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.screen)
            .opacity(0.46)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.18),
                    Color(red: 0.05, green: 0.12, blue: 0.12).opacity(0.56)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.08))
        }
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
        .drawingGroup()
    }

    private func closeHandle(safeTop: CGFloat) -> some View {
        Button(action: dismiss) {
            Capsule()
                .fill(.white.opacity(0.58))
                .frame(width: 48, height: 5)
                .frame(width: 96, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, max(safeTop + 8, 22))
        .accessibilityLabel("Fermer le lecteur")
    }

    private var metadataRow: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trackTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)

                if let primaryArtist {
                    Button {
                        openArtist(primaryArtist)
                    } label: {
                        HStack(spacing: 6) {
                            Text(artistLine)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .opacity(0.72)
                        }
                        .font(.title3.weight(.regular))
                        .foregroundStyle(.white.opacity(0.78))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ouvrir l'artiste \(primaryArtist.name)")
                } else {
                    Text(artistLine)
                        .font(.title3.weight(.regular))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                playerStatus
            }
            .frame(minHeight: 74, alignment: .bottomLeading)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                PlayerGlassIconButton(systemName: "star", size: 40) {}
                PlayerGlassIconButton(systemName: AppIcons.more, size: 40) {}
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var playerStatus: some View {
        Text(playerStatusMessage ?? " ")
            .font(.caption.weight(.semibold))
            .foregroundStyle(playerStatusColor)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .opacity(playerStatusMessage == nil ? 0 : 1)
            .frame(height: 16, alignment: .leading)
            .accessibilityHidden(playerStatusMessage == nil)
    }

    private var transportControls: some View {
        HStack(spacing: 46) {
            PlayerTransportButton(systemName: AppIcons.previous, size: 34) {
                player.previous()
            }

            PlayerPlayPauseButton(isPlaying: showsPauseIcon) {
                player.togglePlayPause()
            }

            PlayerTransportButton(systemName: AppIcons.next, size: 34) {
                player.next()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .accessibilityElement(children: .contain)
    }

    private var volumeControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.62))

            PlayerVolumeBar(
                value: Double(player.outputVolume),
                setValue: { player.setVolume(to: Float($0)) }
            )

            Image(systemName: "speaker.wave.2.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(height: 34)
    }

    private var bottomUtilities: some View {
        HStack {
            PlayerGlassIconButton(systemName: AppIcons.lyrics, size: 42) {
                if let track = player.currentTrack {
                    showLyrics(track)
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 0) {
                PlayerUtilityButton(systemName: player.queue.repeatMode.symbolName, isActive: player.queue.repeatMode != .off) {
                    player.cycleRepeatMode()
                }

                Divider()
                    .overlay(.white.opacity(0.18))
                    .padding(.vertical, 9)

                PlayerUtilityButton(systemName: AppIcons.shuffle, isActive: player.queue.shuffleEnabled) {
                    player.toggleShuffle()
                }
            }
            .frame(width: 118, height: 40)
            .playerNativeLiquidGlass(in: Capsule())

            Spacer(minLength: 16)

            PlayerGlassIconButton(systemName: AppIcons.queue, size: 42) {
                showQueue()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var trackTitle: String {
        player.currentTrack?.title ?? "Aucun titre"
    }

    private var artistLine: String {
        let value = player.currentTrack?.artistLine.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "MusicGlass" : value
    }

    private var primaryArtist: Artist? {
        let trackArtists = player.currentTrack?.artists ?? []
        let albumArtists = player.currentTrack?.album?.artists ?? []
        if let artist = (trackArtists + albumArtists).first(where: { artist in
            guard let browseId = artist.browseId else { return false }
            return !browseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            return artist
        }

        let name = artistLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "MusicGlass" else { return nil }
        return Artist(id: name.lowercased(), browseId: nil, name: name)
    }

    private var displayedDuration: TimeInterval {
        max(player.duration ?? player.currentTrack?.duration ?? 0, 0)
    }

    private var previousSwipeArtworkURL: URL? {
        guard player.progress <= 5,
              let currentIndex = player.queue.currentIndex,
              !player.queue.tracks.isEmpty
        else { return nil }

        let previousIndex = currentIndex - 1
        if player.queue.tracks.indices.contains(previousIndex) {
            return player.queue.tracks[previousIndex].bestThumbnailURL
        }

        if player.queue.repeatMode == .all, let last = player.queue.tracks.last {
            return last.bestThumbnailURL
        }

        return nil
    }

    private var nextSwipeArtworkURL: URL? {
        guard let currentIndex = player.queue.currentIndex,
              !player.queue.tracks.isEmpty
        else { return nil }

        let nextIndex = currentIndex + 1
        if player.queue.tracks.indices.contains(nextIndex) {
            return player.queue.tracks[nextIndex].bestThumbnailURL
        }

        if player.queue.repeatMode == .all, let first = player.queue.tracks.first {
            return first.bestThumbnailURL
        }

        return nil
    }

    private var clampedProgress: TimeInterval {
        min(max(player.progress, 0), displayedDuration > 0 ? displayedDuration : max(player.progress, 0))
    }

    private var showsPauseIcon: Bool {
        switch player.state {
        case .playing, .buffering, .loading:
            return true
        case .idle, .paused, .failed:
            return false
        }
    }

    private var playerStatusMessage: String? {
        switch player.state {
        case .loading:
            "Préparation du flux"
        case .buffering:
            "Mise en mémoire"
        case .failed(let message):
            message
        case .idle, .playing, .paused:
            nil
        }
    }

    private var playerStatusColor: Color {
        if case .failed = player.state {
            return .red.opacity(0.9)
        }
        return .white.opacity(0.62)
    }
}

private struct PlayerProgressSection: View {
    @ObservedObject var tracker = PlayerProgressTracker.shared
    var player: AVPlayerEngine

    private var clampedProgress: TimeInterval {
        let duration = max(tracker.duration, 0)
        return min(max(tracker.progress, 0), duration > 0 ? duration : max(tracker.progress, 0))
    }

    var body: some View {
        PlayerProgressBar(
            progress: clampedProgress,
            duration: max(tracker.duration, 0),
            seek: { player.seek(to: $0) }
        )
    }
}

private extension UIApplication {
    static var musicGlassSafeAreaInsets: UIEdgeInsets {
        shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
    }
}

private struct PlayerProgressBar: View {
    var progress: TimeInterval
    var duration: TimeInterval
    var seek: (TimeInterval) -> Void

    @State private var dragProgress: TimeInterval? = nil

    private var effectiveProgress: TimeInterval {
        dragProgress ?? progress
    }

    private var fraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(effectiveProgress / duration, 0), 1))
    }

    private var remainingTimeLabel: String {
        guard duration > 0 else { return "--:--" }
        return "-\(max(duration - effectiveProgress, 0).musicTimeString)"
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let fillWidth = max(width * fraction, 0)
                let knobSize: CGFloat = 18
                let knobOffset = min(max(fillWidth - (knobSize / 2), 0), max(width - knobSize, 0))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .frame(height: 6)

                    Capsule()
                        .fill(.white.opacity(0.88))
                        .frame(width: fillWidth, height: 6)

                    Circle()
                        .fill(.white)
                        .frame(width: knobSize, height: knobSize)
                        .shadow(color: .black.opacity(0.24), radius: 10, y: 3)
                        .offset(x: knobOffset)
                        .opacity(duration > 0 ? 1 : 0)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0, width > 0 else { return }
                            let ratio = min(max(value.location.x / width, 0), 1)
                            dragProgress = duration * ratio
                        }
                        .onEnded { _ in
                            if let finalProgress = dragProgress {
                                seek(finalProgress)
                            }
                            // Force instantaneous reset to prevent visual snapback animation
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                dragProgress = nil
                            }
                        }
                )
            }
            .frame(height: 24)
            .accessibilityLabel("Progression")
            .accessibilityValue("\(effectiveProgress.musicTimeString) sur \(duration.musicTimeString)")

            HStack {
                Text(effectiveProgress.musicTimeString)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))

                Spacer()

                Text(remainingTimeLabel)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.44))
            }
        }
    }
}

private struct PlayerVolumeBar: View {
    var value: Double
    var setValue: (Double) -> Void

    private var fraction: CGFloat {
        CGFloat(min(max(value, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fillWidth = width * fraction
            let knobSize: CGFloat = 14
            let knobOffset = min(max(fillWidth - (knobSize / 2), 0), max(width - knobSize, 0))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(height: 5)

                Capsule()
                    .fill(.white.opacity(0.84))
                    .frame(width: fillWidth, height: 5)

                Circle()
                    .fill(.white.opacity(0.96))
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.20), radius: 8, y: 2)
                    .offset(x: knobOffset)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        let ratio = min(max(value.location.x / width, 0), 1)
                        setValue(Double(ratio))
                    }
            )
        }
        .frame(height: 22)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value * 100)) %")
    }
}

private struct PlayerTransportButton: View {
    var systemName: String
    var size: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: max(58, size + 18), height: max(58, size + 18))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .accessibilityLabel(systemName)
    }
}

private struct PlayerPlayPauseButton: View {
    var isPlaying: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: AppIcons.play)
                    .opacity(isPlaying ? 0 : 1)

                Image(systemName: AppIcons.pause)
                    .opacity(isPlaying ? 1 : 0)
            }
            .font(.system(size: 54, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 92, height: 92)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .transaction { transaction in
            transaction.animation = nil
        }
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        .accessibilityLabel(isPlaying ? "Pause" : "Lecture")
    }
}

private struct PlayerGlassIconButton: View {
    var systemName: String
    var size: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: size, height: size)
        .playerNativeLiquidGlass(in: Circle())
        .accessibilityLabel(systemName)
    }
}

private struct PlayerUtilityButton: View {
    var systemName: String
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isActive ? .white : .white.opacity(0.72))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func playerNativeLiquidGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(true), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1))
        }
    }
}


private struct SwipeablePlayerArtworkView: View {
    var url: URL?
    var previousURL: URL?
    var nextURL: URL?
    var size: CGFloat
    var identity: String?
    var previousRestartsCurrentTrack: Bool
    var onPrevious: () -> Void
    var onNext: () -> Void

    @State private var axisLock: ArtworkSwipeAxis?
    @State private var offsetX: CGFloat = 0
    @State private var visualOpacity: CGFloat = 1
    @State private var visualScale: CGFloat = 1
    @State private var isCommitting = false
    @State private var commitDirection: CGFloat = 0

    private var pageStride: CGFloat {
        size + 14
    }

    private var artworkIdentity: String {
        identity ?? url?.absoluteString ?? "empty-artwork"
    }

    var body: some View {
        ZStack {
            HStack(spacing: 14) {
                PlayerArtworkView(url: previousURL ?? url, size: size, showsShadow: false)

                PlayerArtworkView(url: url, size: size, showsShadow: false)
                    .id(artworkIdentity)

                PlayerArtworkView(url: nextURL ?? url, size: size, showsShadow: false)
            }
            .frame(width: (size * 3) + 28, height: size)
            .background(Color.black.opacity(0.001))
            .offset(x: offsetX)
            .scaleEffect(visualScale)
            .opacity(visualOpacity)
            .drawingGroup()
        }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 34, y: 18)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .simultaneousGesture(swipeGesture)
            .onChange(of: artworkIdentity) { _, _ in
                guard isCommitting else { return }
                finalizeCommittedArtwork()
            }
            .accessibilityAction(named: "Titre precedent") {
                onPrevious()
            }
            .accessibilityAction(named: "Titre suivant") {
                onNext()
            }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard !isCommitting else { return }
                updateDragLock(for: value.translation)

                guard axisLock == .horizontal else {
                    if axisLock == .vertical {
                        resetHorizontalStateWithoutAnimation()
                    }
                    return
                }
                let resistance: CGFloat = value.translation.width > 0 && previousRestartsCurrentTrack ? 0.42 : 1
                let rawOffset = value.translation.width * resistance
                offsetX = min(max(rawOffset, -pageStride), pageStride)
                let progress = min(abs(offsetX) / max(pageStride, 1), 1)
                
                // Optimized visual updates: only update scale/opacity if they change meaningfully
                let newOpacity = 1 - (progress * 0.04)
                let newScale = 1 - (progress * 0.012)
                if abs(visualOpacity - newOpacity) > 0.005 { visualOpacity = newOpacity }
                if abs(visualScale - newScale) > 0.005 { visualScale = newScale }
            }
            .onEnded { value in
                guard !isCommitting else { return }
                defer { axisLock = nil }
                guard axisLock == .horizontal else {
                    return
                }

                let widthThreshold = size * 0.22
                let predictedThreshold = size * 0.32
                let translation = value.translation.width
                let predicted = value.predictedEndTranslation.width

                if translation > widthThreshold || predicted > predictedThreshold {
                    if previousRestartsCurrentTrack {
                        onPrevious()
                        resetArtwork()
                    } else {
                        commitSwipe(direction: 1, action: onPrevious)
                    }
                } else if translation < -widthThreshold || predicted < -predictedThreshold {
                    commitSwipe(direction: -1, action: onNext)
                } else {
                    resetArtwork()
                }
            }
    }

    private func updateDragLock(for translation: CGSize) {
        if axisLock == .vertical {
            return
        }

        guard axisLock == nil else { return }
        let absX = abs(translation.width)
        let absY = abs(translation.height)
        guard absX > 8 || absY > 8 else { return }

        if absX > absY * 1.25 {
            axisLock = .horizontal
        } else if absY > absX * 1.1 {
            axisLock = .vertical
        }
    }

    private func commitSwipe(direction: CGFloat, action: @escaping () -> Void) {
        isCommitting = true
        commitDirection = direction

        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86)) {
            offsetX = direction * pageStride
            visualOpacity = 1
            visualScale = 1
        }

        // Delay the actual track change to let the animation breathe
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }

        // Safety reset in case the identity change doesn't trigger
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if isCommitting {
                finalizeCommittedArtwork()
            }
        }
    }

    private func finalizeCommittedArtwork() {
        withoutAnimation {
            offsetX = 0
            visualOpacity = 1
            visualScale = 1
            isCommitting = false
            commitDirection = 0
        }
    }

    private func resetArtwork() {
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.1)) {
            offsetX = 0
            visualOpacity = 1
            visualScale = 1
        }
    }

    private func resetHorizontalStateWithoutAnimation() {
        guard offsetX != 0 || visualOpacity != 1 || visualScale != 1 else { return }
        withoutAnimation {
            offsetX = 0
            visualOpacity = 1
            visualScale = 1
        }
    }

    private func withoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            updates()
        }
    }
}

private enum ArtworkSwipeAxis {
    case horizontal
    case vertical
}

private struct ClearFullScreenCoverBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        clearPresentationBackground(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        clearPresentationBackground(from: uiView)
    }

    private func clearPresentationBackground(from view: UIView) {
        DispatchQueue.main.async {
            var parent: UIView? = view
            while let current = parent {
                current.backgroundColor = .clear
                current.isOpaque = false
                parent = current.superview
            }
            view.window?.backgroundColor = .clear
        }
    }
}

private struct PlayerArtworkView: View {
    var url: URL?
    var size: CGFloat
    var showsShadow = true

    @StateObject private var loader = PlayerArtworkLoader()

    var body: some View {
        if showsShadow {
            artworkContent
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 34, y: 18)
                .task(id: url) {
                    await loader.load(from: url, targetSize: size)
                }
                .accessibilityHidden(true)
        } else {
            artworkContent
                .frame(width: size, height: size)
                .clipped()
                .task(id: url) {
                    await loader.load(from: url, targetSize: size)
                }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var artworkContent: some View {
        ZStack {
            if showsShadow {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.08))
            } else {
                Rectangle()
                    .fill(.clear)
            }

            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                if showsShadow {
                    ArtworkView(url: url, size: size, cornerRadius: 14)
                } else {
                    Rectangle()
                        .fill(.white.opacity(0.001))
                        .frame(width: size, height: size)
                }
            }
        }
    }
}

@MainActor
private final class PlayerArtworkLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private static let cache: NSCache<AnyObject, UIImage> = {
        let cache = NSCache<AnyObject, UIImage>()
        cache.countLimit = 150
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
        return cache
    }()
    private var currentURL: URL?

    func load(from url: URL?, targetSize: CGFloat = 350) async {
        currentURL = url
        image = nil

        guard let url else { return }
        let cacheKey = "\(url.absoluteString)_\(Int(targetSize))" as NSString
        if let cached = Self.cache.object(forKey: cacheKey) {
            image = cached
            return
        }

        do {
            let candidates = PlayerArtworkURLResolver.candidates(for: url)
            let scale = await UIScreen.main.scale
            let result = try await Task.detached(priority: .userInitiated) { [scale] () -> UIImage in
                let rawImage = try await self.loadBestImage(from: candidates)
                let processed = rawImage.musicGlassPreparedArtwork(for: url)
                
                // Downsample
                let finalSize = CGSize(width: targetSize, height: targetSize)
                UIGraphicsBeginImageContextWithOptions(finalSize, false, 1.0)
                processed.draw(in: CGRect(origin: .zero, size: finalSize))
                let downsampled = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                return downsampled ?? processed
            }.value
            
            guard currentURL == url else { return }
            Self.cache.setObject(result, forKey: cacheKey)
            image = result
        } catch {
            image = nil
        }
    }

    private func loadBestImage(from urls: [URL]) async throws -> UIImage {
        var bestImage: UIImage?
        var bestScore: CGFloat = 0
        var lastError: Error?

        for candidate in urls {
            do {
                let (data, response) = try await URLSession.shared.data(from: candidate)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200 ... 299).contains(httpResponse.statusCode) {
                    continue
                }
                guard let image = UIImage(data: data), let cgImage = image.cgImage else { continue }
                let score = CGFloat(cgImage.width * cgImage.height)
                if score > bestScore {
                    bestScore = score
                    bestImage = image
                }
                if score >= 900_000 {
                    break
                }
            } catch {
                lastError = error
            }
        }

        if let bestImage {
            return bestImage
        }
        throw lastError ?? URLError(.badServerResponse)
    }
}

private enum PlayerArtworkURLResolver {
    static func cacheKey(for url: URL) -> URL {
        candidates(for: url).first ?? url
    }

    static func candidates(for url: URL) -> [URL] {
        var urls: [URL] = []

        if let upgradedGoogleArtwork = upgradedGoogleArtworkURL(from: url) {
            urls.append(upgradedGoogleArtwork)
        }

        urls.append(contentsOf: upgradedYouTubeVideoURLs(from: url))
        urls.append(url)

        return urls.uniqued()
    }

    private static func upgradedGoogleArtworkURL(from url: URL) -> URL? {
        guard let host = url.host, host.contains("googleusercontent.com") else { return nil }
        let absolute = url.absoluteString
        let pattern = #"=w\d+-h\d+[^/?#]*$"#
        if let range = absolute.range(of: pattern, options: .regularExpression) {
            return URL(string: absolute.replacingCharacters(in: range, with: "=w1200-h1200-l90-rj"))
        }
        return URL(string: absolute + "=w1200-h1200-l90-rj")
    }

    private static func upgradedYouTubeVideoURLs(from url: URL) -> [URL] {
        guard let videoId = youtubeVideoId(from: url) else { return [] }
        return [
            "https://i.ytimg.com/vi/\(videoId)/maxresdefault.jpg",
            "https://i.ytimg.com/vi/\(videoId)/sddefault.jpg",
            "https://i.ytimg.com/vi/\(videoId)/hq720.jpg",
            "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
        ].compactMap(URL.init(string:))
    }

    private static func youtubeVideoId(from url: URL) -> String? {
        let components = url.pathComponents
        guard let viIndex = components.firstIndex(of: "vi"),
              components.indices.contains(viIndex + 1)
        else { return nil }
        return components[viIndex + 1]
    }
}

private extension UIImage {
    func musicGlassPreparedArtwork(for url: URL) -> UIImage {
        guard let host = url.host,
              host.contains("ytimg.com"),
              let cgImage
        else {
            return self
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return self }

        let aspectRatio = width / height
        guard !(0.92 ... 1.08).contains(aspectRatio) else {
            return self
        }

        let squareSide = min(width, height)
        let cropRect = CGRect(
            x: (width - squareSide) / 2,
            y: (height - squareSide) / 2,
            width: squareSide,
            height: squareSide
        )

        guard let cropped = cgImage.cropping(to: cropRect.integral) else { return self }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}
