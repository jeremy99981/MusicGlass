import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var cacheSizeText = "Calculating..."
    @Published var debugLogsEnabled = false
    @Published var audioQuality = "Auto"
    @Published var theme = "System" {
        didSet {
            UserDefaults.standard.set(theme, forKey: "appTheme")
        }
    }

    let authService: AuthService
    private let cacheManager: PlaybackCacheManager

    init(cacheManager: PlaybackCacheManager, authService: AuthService) {
        self.cacheManager = cacheManager
        self.authService = authService
        if let savedTheme = UserDefaults.standard.string(forKey: "appTheme"),
           !savedTheme.isEmpty {
            theme = savedTheme
        }
    }

    func loadCacheSize() {
        let size = cacheManager.cacheSize()
        cacheSizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    func clearCache() {
        cacheManager.clear()
        loadCacheSize()
    }
}
