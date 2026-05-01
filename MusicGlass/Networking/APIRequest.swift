import Foundation

struct APIRequest<Body: Encodable & Sendable>: Sendable {
    var method: String
    var url: URL
    var headers: [String: String]
    var body: Body?
    var timeout: TimeInterval

    init(
        method: String = "GET",
        url: URL,
        headers: [String: String] = [:],
        body: Body? = nil,
        timeout: TimeInterval = 30
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

struct EmptyBody: Encodable, Sendable {}
