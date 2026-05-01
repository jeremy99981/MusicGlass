import Foundation
import os

enum AppLogger {
    static let networking = Logger(subsystem: "com.musicglass.app", category: "networking")
    static let playback = Logger(subsystem: "com.musicglass.app", category: "playback")
    static let persistence = Logger(subsystem: "com.musicglass.app", category: "persistence")
    static let youtube = Logger(subsystem: "com.musicglass.app", category: "youtube-music")
}
