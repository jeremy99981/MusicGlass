import Foundation

struct Lyrics: Identifiable, Codable, Hashable, Sendable {
    var id: String { trackId }
    var trackId: String
    var plainText: String
    var syncedLines: [LyricLine]
    var provider: String
    var language: String?
}

struct LyricLine: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(time)-\(text)" }
    var time: TimeInterval
    var text: String
}
