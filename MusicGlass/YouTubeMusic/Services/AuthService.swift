import Foundation
import CryptoKit
import WebKit

@MainActor
final class AuthService: ObservableObject {
    @Published var cookies: [HTTPCookie] = []
    @Published var dataSyncId: String? = nil
    @Published var visitorData: String? = nil
    private let storageKey = "MusicGlass.AuthCookies"
    private let cookieRecordsKey = "MusicGlass.AuthCookieRecords"
    private let dataSyncIdKey = "MusicGlass.DataSyncId"
    private let visitorDataKey = "MusicGlass.VisitorData"

    var isAuthenticated: Bool {
        sapisid != nil && dataSyncId?.isEmpty == false
    }

    var sapisid: String? {
        authCookiesForYouTubeMusic.first(where: { $0.name == "SAPISID" })?.value
    }

    init() {
        let restoredFromCurrentStorage = restoreCookies()
        guard restoredFromCurrentStorage else {
            clearLegacySession()
            return
        }

        self.dataSyncId = Self.normalizedDataSyncId(UserDefaults.standard.string(forKey: dataSyncIdKey))
        self.visitorData = UserDefaults.standard.string(forKey: visitorDataKey)
        if let dataSyncId {
            UserDefaults.standard.set(dataSyncId, forKey: dataSyncIdKey)
        }
        guard isAuthenticated else {
            AppLogger.youtube.warning("Auth: stored session is incomplete, clearing it")
            clear()
            return
        }
        logCookieSummary(prefix: "Auth: restored session")
    }

    func saveAuthData(cookies: [HTTPCookie], dataSyncId: String?, visitorData: String?) {
        let validCookies = cookies.filter { !$0.isExpired }
        let normalizedDataSyncId = Self.normalizedDataSyncId(dataSyncId)
        self.cookies = validCookies
        self.dataSyncId = normalizedDataSyncId
        self.visitorData = visitorData
        let records = validCookies.map(CookieRecord.init(cookie:))
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: cookieRecordsKey)
        }
        UserDefaults.standard.removeObject(forKey: storageKey)
        if let normalizedDataSyncId {
            UserDefaults.standard.set(normalizedDataSyncId, forKey: dataSyncIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: dataSyncIdKey)
        }
        if let visitorData {
            UserDefaults.standard.set(visitorData, forKey: visitorDataKey)
        } else {
            UserDefaults.standard.removeObject(forKey: visitorDataKey)
        }
        logCookieSummary(prefix: "Auth: saved session")
    }

    func clear() {
        self.cookies = []
        self.dataSyncId = nil
        self.visitorData = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: cookieRecordsKey)
        UserDefaults.standard.removeObject(forKey: dataSyncIdKey)
        UserDefaults.standard.removeObject(forKey: visitorDataKey)
    }

    func logout() async {
        clear()
        
        let websiteDataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dataStore = WKWebsiteDataStore.default()
        let records = await dataStore.dataRecords(ofTypes: websiteDataTypes)
        
        let targetRecords = records.filter { record in
            let name = record.displayName.lowercased()
            return name.contains("youtube") || name.contains("google")
        }
        
        await dataStore.removeData(ofTypes: websiteDataTypes, for: targetRecords)
        AppLogger.youtube.notice("Auth: WebKit YouTube/Google cookies and data cleared")
    }

    func getCookieHeader() -> String? {
        let headerCookies = authCookiesForYouTubeMusic
        guard !headerCookies.isEmpty else { return nil }
        let pairs = headerCookies.map { "\($0.name)=\($0.value)" }
        guard !pairs.isEmpty else { return nil }
        AppLogger.youtube.notice(
            "Auth: cookie header prepared with \(headerCookies.count, privacy: .public) cookies, SAPISID=\(self.sapisid != nil, privacy: .public), dataSync=\(self.dataSyncId != nil, privacy: .public)"
        )
        return pairs.joined(separator: "; ")
    }

    func getAuthorizationHeader() -> String? {
        guard let sapisid = self.sapisid else { return nil }
        let timestamp = Int(Date().timeIntervalSince1970)
        let origin = "https://music.youtube.com"
        let payload = "\(timestamp) \(sapisid) \(origin)"
        let hash = Insecure.SHA1.hash(data: Data(payload.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return "SAPISIDHASH \(timestamp)_\(hashString)"
    }

    private var authCookiesForYouTubeMusic: [HTTPCookie] {
        let validCookies = cookies.filter { !$0.isExpired }
        let youtubeCookies = validCookies
            .filter { $0.domain.isYouTubeCookieDomain }
            .sortedForCookieHeader()
            .deduplicatedByName()
        if youtubeCookies.contains(where: { $0.name == "SAPISID" }) {
            return youtubeCookies
        }

        // Some WebKit sessions expose SAPISID on google.com only. In that case,
        // fall back to the broader Google/YouTube set so the signed SAPISID value
        // matches the Cookie header that will be sent.
        return validCookies
            .filter { $0.domain.isGoogleOrYouTubeCookieDomain }
            .sortedForCookieHeader()
            .deduplicatedByName()
    }

    @discardableResult
    private func restoreCookies() -> Bool {
        if let data = UserDefaults.standard.data(forKey: cookieRecordsKey),
           let records = try? JSONDecoder().decode([CookieRecord].self, from: data) {
            self.cookies = records.compactMap(\.httpCookie).filter { !$0.isExpired }
            return true
        }
        return false
    }

    private func clearLegacySession() {
        if UserDefaults.standard.data(forKey: storageKey) != nil ||
            UserDefaults.standard.string(forKey: dataSyncIdKey) != nil {
            AppLogger.youtube.warning("Auth: legacy cookie archive ignored, forcing a fresh YouTube Music login")
        }
        self.cookies = []
        self.dataSyncId = nil
        self.visitorData = UserDefaults.standard.string(forKey: visitorDataKey)
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: dataSyncIdKey)
    }

    private static func normalizedDataSyncId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.components(separatedBy: "||").first ?? trimmed
        return normalized.isEmpty ? nil : normalized
    }

    private func logCookieSummary(prefix: String) {
        let validCookies = cookies.filter { !$0.isExpired }
        let youtubeCount = validCookies.filter { $0.domain.isYouTubeCookieDomain }.count
        let googleCount = validCookies.filter { $0.domain.lowercased().contains("google.com") }.count
        let names = Set(validCookies.map(\.name)).sorted().joined(separator: ",")
        AppLogger.youtube.notice(
            "\(prefix, privacy: .public): total=\(validCookies.count, privacy: .public), youtube=\(youtubeCount, privacy: .public), google=\(googleCount, privacy: .public), SAPISID=\(self.sapisid != nil, privacy: .public), dataSync=\(self.dataSyncId != nil, privacy: .public), names=\(names, privacy: .public)"
        )
    }
}

private struct CookieRecord: Codable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expiresDate: Date?
    var isSecure: Bool

    init(cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.expiresDate = cookie.expiresDate
        self.isSecure = cookie.isSecure
    }

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .secure: isSecure ? "TRUE" : "FALSE"
        ]
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        return HTTPCookie(properties: properties)
    }
}

private extension HTTPCookie {
    var isExpired: Bool {
        guard let expiresDate else { return false }
        return expiresDate <= Date()
    }
}

private extension String {
    var isYouTubeCookieDomain: Bool {
        let domain = lowercased()
        return domain == "youtube.com" ||
            domain == ".youtube.com" ||
            domain == "music.youtube.com" ||
            domain == ".music.youtube.com" ||
            domain.hasSuffix(".youtube.com")
    }

    var isGoogleOrYouTubeCookieDomain: Bool {
        let domain = lowercased()
        return isYouTubeCookieDomain ||
            domain == "google.com" ||
            domain == ".google.com" ||
            domain.hasSuffix(".google.com")
    }
}

private extension Array where Element == HTTPCookie {
    func sortedForCookieHeader() -> [HTTPCookie] {
        sorted { lhs, rhs in
            if lhs.domain != rhs.domain {
                return lhs.domain.count > rhs.domain.count
            }
            if lhs.path != rhs.path {
                return lhs.path.count > rhs.path.count
            }
            return lhs.name < rhs.name
        }
    }

    func deduplicatedByName() -> [HTTPCookie] {
        var seen = Set<String>()
        return filter { cookie in
            seen.insert(cookie.name).inserted
        }
    }
}
