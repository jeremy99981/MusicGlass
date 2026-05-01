import Foundation

enum AppError: LocalizedError, Sendable {
    case noConnection
    case unsupportedRegion
    case streamUnavailable(String)
    case parsingFailed(String)
    case contentUnavailable
    case authenticationExpired
    case rateLimited
    case artworkUnavailable
    case lyricsUnavailable
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .noConnection:
            "Aucune connexion. Vérifiez votre réseau puis réessayez."
        case .unsupportedRegion:
            "Le service musical ne semble pas disponible dans cette région."
        case .streamUnavailable(let reason):
            reason.isEmpty ? "Ce flux est indisponible." : reason
        case .parsingFailed:
            "La réponse du service musical a changé. Réessayez plus tard."
        case .contentUnavailable:
            "Ce contenu est indisponible."
        case .authenticationExpired:
            "La session a expiré. Vous pourrez vous reconnecter lorsque les comptes seront activés."
        case .rateLimited:
            "Trop de requêtes. Patientez un instant."
        case .artworkUnavailable:
            "La pochette est indisponible."
        case .lyricsUnavailable:
            "Les paroles sont indisponibles."
        case .cancelled:
            "La requête a été annulée."
        case .unknown(let message):
            message
        }
    }
}
