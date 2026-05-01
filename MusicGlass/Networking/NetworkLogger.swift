import Foundation

struct NetworkLogger: Sendable {
    var isEnabled: Bool = false

    func logRequest(_ request: URLRequest) {
        guard isEnabled else { return }
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "<nil>"
        AppLogger.networking.debug("\(method, privacy: .public) \(redact(url), privacy: .public)")
    }

    func logResponse(_ response: HTTPURLResponse, bytes: Int) {
        guard isEnabled else { return }
        AppLogger.networking.debug("HTTP \(response.statusCode, privacy: .public) \(bytes, privacy: .public)b")
    }

    func redact(_ value: String) -> String {
        var redacted = value
        let sensitiveKeys = ["Authorization", "SAPISID", "cookie", "Cookie", "access_token", "refresh_token", "key"]
        for key in sensitiveKeys {
            redacted = redacted.replacingOccurrences(
                of: #"(?i)(\#(key)=)[^&\s]+"#,
                with: "$1<redacted>",
                options: .regularExpression
            )
        }
        return redacted
    }
}
