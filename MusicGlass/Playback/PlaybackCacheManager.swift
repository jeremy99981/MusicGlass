import Foundation

struct PlaybackCacheManager {
    private let fileManager = FileManager.default

    func cacheSize() -> Int64 {
        let urls = [
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
            URLCache.shared.diskCacheURL
        ].compactMap { $0 }

        return urls.reduce(Int64(0)) { total, url in
            total + directorySize(url)
        }
    }

    func clear() {
        URLCache.shared.removeAllCachedResponses()
        guard let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let contents = (try? fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            try? fileManager.removeItem(at: item)
        }
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return enumerator.reduce(Int64(0)) { partial, element in
            guard let url = element as? URL,
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { return partial }
            return partial + Int64(size)
        }
    }
}

private extension URLCache {
    var diskCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("URLCache")
    }
}
