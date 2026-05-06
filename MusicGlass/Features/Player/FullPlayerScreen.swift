import SwiftUI
import UIKit

struct FullPlayerScreen: View {
    @EnvironmentObject private var player: AVPlayerEngine
    @GestureState private var dragOffset: CGFloat = 0

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

                    PlayerArtworkView(url: player.currentTrack?.bestThumbnailURL, size: artworkSize)
                        .padding(.top, isCompact ? 6 : 12)

                    VStack(alignment: .leading, spacing: isCompact ? 14 : 18) {
                        metadataRow

                        PlayerProgressBar(
                            progress: clampedProgress,
                            duration: displayedDuration,
                            seek: { player.seek(to: $0) }
                        )
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
            .offset(y: max(dragOffset, 0))
            .gesture(
                DragGesture(minimumDistance: 20)
                    .updating($dragOffset) { value, state, _ in
                        state = max(value.translation.height, 0)
                    }
                    .onEnded { value in
                        if value.translation.height > 110 || value.predictedEndTranslation.height > 190 {
                            dismiss()
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .background(Color(red: 0.07, green: 0.12, blue: 0.12).ignoresSafeArea())
        .environment(\.colorScheme, .dark)
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

    private var fraction: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(progress / duration, 0), 1))
    }

    private var remainingTimeLabel: String {
        guard duration > 0 else { return "--:--" }
        return "-\(max(duration - progress, 0).musicTimeString)"
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
                            seek(duration * ratio)
                        }
                )
            }
            .frame(height: 24)
            .accessibilityLabel("Progression")
            .accessibilityValue("\(progress.musicTimeString) sur \(duration.musicTimeString)")

            HStack {
                Text(progress.musicTimeString)
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


private struct PlayerArtworkView: View {
    var url: URL?
    var size: CGFloat

    @StateObject private var loader = PlayerArtworkLoader()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.08))

            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
            } else {
                ArtworkView(url: url, size: size, cornerRadius: 14)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 34, y: 18)
        .task(id: url) {
            await loader.load(from: url)
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private final class PlayerArtworkLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private static let cache = NSCache<NSURL, UIImage>()
    private var currentURL: URL?

    func load(from url: URL?) async {
        currentURL = url
        image = nil

        guard let url else { return }
        let cacheKey = PlayerArtworkURLResolver.cacheKey(for: url)
        if let cached = Self.cache.object(forKey: cacheKey as NSURL) {
            image = cached
            return
        }

        do {
            let rawImage = try await loadBestImage(from: PlayerArtworkURLResolver.candidates(for: url))
            guard currentURL == url else { return }
            let processed = rawImage.musicGlassPreparedArtwork(for: url)
            Self.cache.setObject(processed, forKey: cacheKey as NSURL)
            image = processed
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
