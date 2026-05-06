import Foundation

actor InnerTubeClient {
    private let httpClient: HTTPClientProtocol
    private let authService: AuthService
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder
    private let baseURL = URL(string: "https://music.youtube.com/youtubei/v1/")!
    private var visitorData: String?
    private var gl: String
    private var hl: String

    init(
        httpClient: HTTPClientProtocol,
        authService: AuthService,
        gl: String = Locale.current.region?.identifier ?? "US",
        hl: String = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    ) {
        self.httpClient = httpClient
        self.authService = authService
        self.gl = gl.isEmpty ? "US" : gl
        self.hl = hl.isEmpty ? "en" : hl
        self.jsonDecoder = JSONDecoder()
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.outputFormatting = []
    }

    private func getContext(for client: InnerTubeClientDescriptor, includeLogin: Bool = false) async -> InnerTubeContext {
        let authContext = await MainActor.run {
            (authService.dataSyncId, authService.visitorData)
        }
        let activeVisitorData = visitorData ?? authContext.1
        return client.context(gl: gl, hl: hl, visitorData: activeVisitorData, dataSyncId: includeLogin ? authContext.0 : nil)
    }

    func search(query: String, filter: SearchFilter?) async throws -> JSONValue {
        let body = InnerTubeRequestBody(
            context: await getContext(for: .webRemix),
            query: query,
            params: filter?.innerTubeParams
        )
        return try await post(endpoint: "search", body: body, client: .webRemix)
    }

    func browse(browseId: String? = nil, params: String? = nil, continuation: String? = nil, useAuth: Bool = false) async throws -> JSONValue {
        let body = InnerTubeRequestBody(
            context: await getContext(for: .webRemix, includeLogin: useAuth),
            params: params,
            continuation: continuation,
            browseId: browseId
        )
        return try await post(endpoint: "browse", body: body, client: .webRemix, useAuth: useAuth)
    }

    func player(videoId: String) async throws -> JSONValue {
        let body = InnerTubeRequestBody(
            context: await getContext(for: .androidVr),
            videoId: videoId
        )
        return try await post(endpoint: "player", body: body, client: .androidVr)
    }

    func next(videoId: String, playlistId: String? = nil, continuation: String? = nil) async throws -> JSONValue {
        let body = InnerTubeRequestBody(
            context: await getContext(for: .webRemix),
            continuation: continuation,
            videoId: videoId,
            playlistId: playlistId
        )
        return try await post(endpoint: "next", body: body, client: .webRemix)
    }

    func playlistQueue(playlistId: String) async throws -> JSONValue {
        let body = InnerTubeRequestBody(
            context: await getContext(for: .webRemix),
            playlistId: playlistId
        )
        return try await post(endpoint: "next", body: body, client: .webRemix)
    }

    func searchSuggestions(query: String) async throws -> JSONValue {
        let body = InnerTubeRequestBody(
            context: await getContext(for: .webRemix),
            input: query
        )
        return try await post(endpoint: "music/get_search_suggestions", body: body, client: .webRemix)
    }

    /// Fetch user's liked songs from YouTube Music library
    func likedSongs() async throws -> JSONValue {
        let body = InnerTubeRequestBody(
            context: await getContext(for: .webRemix, includeLogin: true),
            browseId: "VLLM"
        )
        let value = try await post(endpoint: "browse", body: body, client: .webRemix, useAuth: true)
        #if DEBUG
        debugLogTopKeys("likedSongs", value)
        #endif
        return value
    }

    /// Fetch user's playlists from YouTube Music library
    func userPlaylists() async throws -> JSONValue {
        let body = InnerTubeRequestBody(
            context: await getContext(for: .webRemix, includeLogin: true),
            browseId: "FEmusic_liked_playlists"
        )
        let value = try await post(endpoint: "browse", body: body, client: .webRemix, useAuth: true)
        #if DEBUG
        debugLogTopKeys("userPlaylists", value)
        #endif
        return value
    }

    /// Fetch user's listening history from YouTube Music
    func ytHistory() async throws -> JSONValue {
        let body = InnerTubeRequestBody(
            context: await getContext(for: .webRemix, includeLogin: true),
            browseId: "FEmusic_history"
        )
        let value = try await post(endpoint: "browse", body: body, client: .webRemix, useAuth: true)
        #if DEBUG
        debugLogTopKeys("ytHistory", value)
        #endif
        return value
    }

    func setLike(videoId: String, liked: Bool) async throws {
        let body = InnerTubeRequestBody(
            context: await getContext(for: .webRemix, includeLogin: true),
            target: InnerTubeRequestBody.LikeTarget(videoId: videoId)
        )
        _ = try await post(endpoint: liked ? "like/like" : "like/removelike", body: body, client: .webRemix, useAuth: true)
        AppLogger.youtube.notice("YT like state updated for \(videoId, privacy: .public): \(liked, privacy: .public)")
    }

    #if DEBUG
    private func debugLogTopKeys(_ label: String, _ value: JSONValue) {
        let topKeys = value.object.keys.sorted().joined(separator: ", ")
        let rendererCount = value.collectObjects(named: "musicResponsiveListItemRenderer").count
        let twoRowCount = value.collectObjects(named: "musicTwoRowItemRenderer").count
        let gridCount = value.collectObjects(named: "gridRenderer").count
        let shelfCount = value.collectObjects(named: "musicShelfRenderer").count
        NSLog("[%@] topKeys: %@", label, topKeys)
        NSLog("[%@] renderers: responsive=%d, twoRow=%d, grid=%d, shelf=%d", label, rendererCount, twoRowCount, gridCount, shelfCount)

        // Check for errors
        if let error = value.string(at: ["error", "message"]) {
            NSLog("[%@] ERROR: %@", label, error)
        }

        // Dump first 2000 chars of JSON to see structure
        if let jsonData = try? JSONEncoder().encode(value),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let preview = String(jsonString.prefix(3000))
            NSLog("[%@] JSON preview: %@", label, preview)
        }
    }
    #endif

    private func post(endpoint: String, body: InnerTubeRequestBody, client: InnerTubeClientDescriptor, useAuth: Bool = false) async throws -> JSONValue {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        guard let url = components.url else { throw AppError.unknown("Invalid InnerTube URL.") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue(client.clientId, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        if client.clientName == "WEB_REMIX" {
            request.setValue("https://music.youtube.com", forHTTPHeaderField: "X-Origin")
            request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
            request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        }
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        let storedVisitorData = await MainActor.run { authService.visitorData }
        let activeVisitorData = visitorData ?? storedVisitorData
        if let activeVisitorData {
            request.setValue(activeVisitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        
        // Fetch auth headers on MainActor (AuthService is @MainActor)
        // Must capture values, NOT mutate request inside @Sendable closure (URLRequest is a struct)
        let (cookieHeader, authHeader): (String?, String?) = await MainActor.run {
            if useAuth && (client.clientName.hasPrefix("WEB") || client.clientName.hasPrefix("TV")) {
                return (authService.getCookieHeader(), authService.getAuthorizationHeader())
            }
            return (nil, nil)
        }
        if let cookieHeader {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            AppLogger.youtube.notice("Auth: Cookie header set")
        } else {
            AppLogger.youtube.notice("Auth: No cookie header for client \(client.clientName, privacy: .public)")
        }
        if let authHeader {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            AppLogger.youtube.notice("Auth: Authorization header set")
        }
        
        request.httpBody = try jsonEncoder.encode(body)

        let data = try await httpClient.data(for: request)
        let value = try jsonDecoder.decode(JSONValue.self, from: data)
        if let errorMessage = value.string(at: ["error", "message"]) {
            AppLogger.youtube.error("InnerTube error on \(endpoint, privacy: .public): \(errorMessage, privacy: .public)")
            throw AppError.unknown(errorMessage)
        }
        if visitorData == nil {
            visitorData = value.string(at: ["responseContext", "visitorData"])
        }
        return value
    }
}
