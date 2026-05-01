import Foundation

struct Thumbnail: Codable, Hashable, Sendable {
    var url: URL
    var width: Int?
    var height: Int?
}
