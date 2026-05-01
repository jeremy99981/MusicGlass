import Foundation

enum NetworkError: LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(Int, Data)
    case decodingFailed(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Le serveur a renvoyé une réponse invalide."
        case .httpStatus(let status, _):
            "Le serveur a renvoyé le code HTTP \(status)."
        case .decodingFailed:
            "La réponse n’a pas pu être décodée."
        case .transport(let error):
            error.localizedDescription
        }
    }
}
