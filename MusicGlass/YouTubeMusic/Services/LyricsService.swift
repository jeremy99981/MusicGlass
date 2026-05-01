import Foundation

protocol LyricsServiceProtocol: Sendable {
    func lyrics(for track: Track) async throws -> Lyrics?
}

struct LRCLibLyricsService: LyricsServiceProtocol {
    private struct LRCLibResponse: Decodable {
        var plainLyrics: String?
        var syncedLyrics: String?
        var lang: String?
    }

    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol) {
        self.httpClient = httpClient
    }

    func lyrics(for track: Track) async throws -> Lyrics? {
        guard !track.title.isEmpty else { return nil }
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artists.first?.name ?? track.artistLine),
            URLQueryItem(name: "album_name", value: track.album?.title),
            URLQueryItem(name: "duration", value: track.duration.map { String(Int($0.rounded())) })
        ].compactMap { item in
            guard let value = item.value, !value.isEmpty else { return nil }
            return item
        }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("MusicGlass/1.0 (third-party music client)", forHTTPHeaderField: "User-Agent")
        do {
            let response = try await httpClient.decoded(LRCLibResponse.self, for: request, decoder: JSONDecoder())
            let synced = parseSyncedLyrics(response.syncedLyrics)
            let plain = response.plainLyrics ?? synced.map(\.text).joined(separator: "\n")
            guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Lyrics(trackId: track.id, plainText: plain, syncedLines: synced, provider: "LRCLib", language: response.lang)
        } catch {
            return nil
        }
    }

    private func parseSyncedLyrics(_ text: String?) -> [LyricLine] {
        guard let text else { return [] }
        return text.split(separator: "\n").compactMap { rawLine in
            let line = String(rawLine)
            guard let end = line.firstIndex(of: "]"), line.first == "[" else { return nil }
            let timeCode = String(line[line.index(after: line.startIndex)..<end])
            let body = String(line[line.index(after: end)...])
            guard let time = parseTimeCode(timeCode), !body.isEmpty else { return nil }
            return LyricLine(time: time, text: body)
        }
    }

    private func parseTimeCode(_ code: String) -> TimeInterval? {
        let parts = code.split(separator: ":")
        guard parts.count == 2,
              let minutes = TimeInterval(parts[0]),
              let seconds = TimeInterval(parts[1])
        else { return nil }
        return minutes * 60 + seconds
    }
}
