import Foundation
import UIKit

struct PlayerItem: Identifiable, Hashable, Sendable {
    var id: String { track.id }
    var track: Track
    var resolvedStreamURL: URL
    var artwork: UIImage?
    var duration: TimeInterval?
}
