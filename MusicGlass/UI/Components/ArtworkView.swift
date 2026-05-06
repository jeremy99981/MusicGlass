import SwiftUI
import UIKit

struct ArtworkView: View {
    var url: URL?
    var size: CGFloat
    var cornerRadius: CGFloat = AppRadius.medium
    var animateArtworkUpdates = false

    @StateObject private var loader = ArtworkImageLoader()

    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.03)),
                        removal: .opacity
                    ))
            } else if url == nil || loader.didFail {
                placeholder
            } else {
                placeholder
                    .redacted(reason: .placeholder)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        .task(id: url) {
            await loader.load(from: url)
        }
        .animation(animateArtworkUpdates ? .spring(response: 0.44, dampingFraction: 0.84) : nil, value: loader.image != nil)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.accent.opacity(0.55), AppColors.secondaryAccent.opacity(0.65), .gray.opacity(0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: AppIcons.music)
                .font(.system(size: max(18, size * 0.28), weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

@MainActor
private final class ArtworkImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var didFail = false

    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 128 * 1024 * 1024 // 128 MB
        return cache
    }()

    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 128 * 1024 * 1024,  // 128 MB memory
            diskCapacity: 512 * 1024 * 1024       // 512 MB disk
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    private var currentURL: URL?

    func load(from url: URL?) async {
        currentURL = url
        image = nil
        didFail = false

        guard let url else { return }
        let cacheKey = ArtworkURLResolver.cacheKey(for: url)
        if let cached = Self.cache.object(forKey: cacheKey as NSURL) {
            image = cached
            return
        }

        do {
            let rawImage = try await loadBestImage(from: ArtworkURLResolver.candidates(for: url))
            guard currentURL == url else { return }
            let processed = rawImage.musicGlassArtworkCrop(for: url)
            Self.cache.setObject(processed, forKey: cacheKey as NSURL, cost: processed.jpegData(compressionQuality: 0.5)?.count ?? 0)
            image = processed
        } catch {
            guard currentURL == url else { return }
            didFail = true
        }
    }

    private func loadBestImage(from urls: [URL]) async throws -> UIImage {
        var bestImage: UIImage?
        var bestScore: CGFloat = 0
        var lastError: Error?

        for candidate in urls {
            do {
                let (data, response) = try await Self.urlSession.data(from: candidate)
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

private enum ArtworkURLResolver {
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
    func musicGlassArtworkCrop(for url: URL) -> UIImage {
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
        let baseSide = min(width, height)
        let squareSide: CGFloat

        if aspectRatio > 1.15 {
            squareSide = min(baseSide * 0.74, width)
        } else if aspectRatio < 0.87 {
            squareSide = min(baseSide * 0.88, height)
        } else {
            return self
        }

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

#Preview {
    ArtworkView(url: Track.preview.bestThumbnailURL, size: 120)
        .padding()
}
