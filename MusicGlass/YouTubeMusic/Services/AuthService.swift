import Foundation
import CryptoKit
import WebKit
import Security

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

@MainActor
final class MusicGlassAuthService: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?

    private let httpClient: HTTPClientProtocol
    private let baseURL: URL

    private let accessTokenKey = "musicglass.api.access_token"
    private let refreshTokenKey = "musicglass.api.refresh_token"
    private let tokenTypeKey = "musicglass.api.token_type"
    private let userStorageKey = "musicglass.api.user"

    init(httpClient: HTTPClientProtocol, baseURL: URL? = nil) {
        self.httpClient = httpClient
        self.baseURL = baseURL ?? MusicGlassAuthService.defaultBaseURL
        restoreSession()
    }

    var isAuthenticated: Bool {
        session?.accessToken.isEmpty == false
    }

    func clearError() {
        lastErrorMessage = nil
    }

    func signup(name: String, email: String, password: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        clearError()

        do {
            let url = baseURL.appendingPathComponent("auth/signup")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(SignupRequest(email: email, name: name, password: password))

            _ = try await httpClient.decoded(RemoteUser.self, for: request, decoder: JSONDecoder())
            return await login(email: email, password: password)
        } catch {
            lastErrorMessage = mapError(error, defaultMessage: "Impossible de créer le compte.")
            return false
        }
    }

    func login(email: String, password: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        clearError()

        do {
            let url = baseURL.appendingPathComponent("auth/login")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(LoginRequest(email: email, password: password))

            let tokens = try await httpClient.decoded(AuthTokensResponse.self, for: request, decoder: JSONDecoder())
            var user = RemoteUser(id: nil, email: email, first_name: nil, last_name: nil, name: nil)
            if let userID = tokens.inferredUserID {
                user = try await fetchProfile(userID: userID, accessToken: tokens.access_token, tokenType: tokens.token_type)
            }

            try persist(tokens: tokens, user: user)
            session = Session(
                user: user.asLocalUser,
                accessToken: tokens.access_token,
                refreshToken: tokens.refresh_token,
                tokenType: tokens.token_type
            )
            return true
        } catch {
            lastErrorMessage = mapError(error, defaultMessage: "Connexion impossible.")
            return false
        }
    }

    func logout() {
        KeychainStore.remove(accessTokenKey)
        KeychainStore.remove(refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: tokenTypeKey)
        UserDefaults.standard.removeObject(forKey: userStorageKey)
        session = nil
        lastErrorMessage = nil
    }

    private func fetchProfile(userID: Int, accessToken: String, tokenType: String) async throws -> RemoteUser {
        let url = baseURL.appendingPathComponent("users/\(userID)/profile")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(tokenType) \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await httpClient.decoded(RemoteUser.self, for: request, decoder: JSONDecoder())
    }

    private func persist(tokens: AuthTokensResponse, user: RemoteUser) throws {
        try KeychainStore.set(tokens.access_token, for: accessTokenKey)
        try KeychainStore.set(tokens.refresh_token, for: refreshTokenKey)
        UserDefaults.standard.set(tokens.token_type, forKey: tokenTypeKey)
        let encodedUser = try JSONEncoder().encode(user)
        UserDefaults.standard.set(encodedUser, forKey: userStorageKey)
    }

    private func restoreSession() {
        guard let accessToken = try? KeychainStore.get(accessTokenKey), !accessToken.isEmpty,
              let refreshToken = try? KeychainStore.get(refreshTokenKey), !refreshToken.isEmpty
        else {
            session = nil
            return
        }

        let tokenType = UserDefaults.standard.string(forKey: tokenTypeKey) ?? "Bearer"
        let userData = UserDefaults.standard.data(forKey: userStorageKey)
        let user = (try? JSONDecoder().decode(RemoteUser.self, from: userData ?? Data()))?.asLocalUser
            ?? LocalUser(id: nil, name: "Utilisateur", email: nil)
        session = Session(
            user: user,
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType
        )
    }

    private func mapError(_ error: Error, defaultMessage: String) -> String {
        if let networkError = error as? NetworkError {
            if case let .httpStatus(code, data) = networkError {
                let apiError = try? JSONDecoder().decode(ErrorResponse.self, from: data)
                let reason = apiError?.error ?? HTTPURLResponse.localizedString(forStatusCode: code)
                return "\(reason.capitalized) (\(code))"
            }
            return networkError.localizedDescription
        }
        return error.localizedDescription.isEmpty ? defaultMessage : error.localizedDescription
    }
}

extension MusicGlassAuthService {
    struct Session {
        let user: LocalUser
        let accessToken: String
        let refreshToken: String
        let tokenType: String
    }

    struct LocalUser {
        let id: Int?
        let name: String
        let email: String?
    }
}

private extension MusicGlassAuthService {
    struct SignupRequest: Encodable {
        let email: String
        let name: String
        let password: String
    }

    struct LoginRequest: Encodable {
        let email: String
        let password: String
    }

    struct AuthTokensResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let token_type: String

        var inferredUserID: Int? {
            access_token.jwtPayloadValue(for: "user_id") ??
                access_token.jwtPayloadValue(for: "id") ??
                access_token.jwtPayloadValue(for: "sub")
        }
    }

    struct ErrorResponse: Decodable {
        let error: String
    }

    struct RemoteUser: Codable {
        let id: Int?
        let email: String?
        let first_name: String?
        let last_name: String?
        let name: String?

        var asLocalUser: LocalUser {
            let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let resolvedName, !resolvedName.isEmpty {
                return LocalUser(id: id, name: resolvedName, email: resolvedEmail)
            }
            if let resolvedEmail, !resolvedEmail.isEmpty {
                return LocalUser(id: id, name: resolvedEmail, email: resolvedEmail)
            }
            let composed = [first_name, last_name]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !composed.isEmpty {
                return LocalUser(id: id, name: composed, email: resolvedEmail)
            }
            return LocalUser(id: id, name: "Utilisateur", email: resolvedEmail)
        }
    }

    static var defaultBaseURL: URL {
        if let fromEnv = ProcessInfo.processInfo.environment["MUSICGLASS_API_BASE_URL"],
           let url = URL(string: fromEnv), !fromEnv.isEmpty {
            return url
        }
        if let fromDefaults = UserDefaults.standard.string(forKey: "musicglass.api.base_url"),
           let url = URL(string: fromDefaults), !fromDefaults.isEmpty {
            return url
        }
        return URL(string: "http://localhost:8081")!
    }
}

private enum KeychainStore {
    static func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.musicglass.auth",
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    static func get(_ key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.musicglass.auth",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.musicglass.auth"
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum KeychainError: Error {
    case unhandled(OSStatus)
}

private extension String {
    func jwtPayloadValue(for key: String) -> Int? {
        let parts = split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payloadPart = String(parts[1])
        guard let data = Data(base64URLEncoded: payloadPart),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let intValue = json[key] as? Int {
            return intValue
        }
        if let stringValue = json[key] as? String, let intValue = Int(stringValue) {
            return intValue
        }
        return nil
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var encoded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (encoded.count % 4)
        if padding < 4 {
            encoded.append(String(repeating: "=", count: padding))
        }
        self.init(base64Encoded: encoded)
    }
}
