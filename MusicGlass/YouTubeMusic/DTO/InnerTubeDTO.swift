import Foundation

struct InnerTubeRequestBody: Encodable, Sendable {
    var context: InnerTubeContext
    var query: String?
    var params: String?
    var continuation: String?
    var browseId: String?
    var videoId: String?
    var playlistId: String?
    var playlistSetVideoId: String?
    var index: Int?
    var input: String?
    var playbackContext: PlaybackContext?
    var target: LikeTarget?

    struct PlaybackContext: Encodable, Sendable {
        var contentPlaybackContext: ContentPlaybackContext

        struct ContentPlaybackContext: Encodable, Sendable {
            var signatureTimestamp: Int
        }
    }

    struct LikeTarget: Encodable, Sendable {
        var videoId: String?
        var playlistId: String?
    }
}

struct InnerTubeContext: Encodable, Sendable {
    var client: InnerTubeClientDescriptor.ContextClient
    var user: User = User()

    struct User: Encodable, Sendable {
        var onBehalfOfUser: String?
    }
}

struct InnerTubeClientDescriptor: Sendable {
    var clientName: String
    var clientVersion: String
    var clientId: String
    var userAgent: String
    var osName: String?
    var osVersion: String?
    var deviceMake: String?
    var deviceModel: String?

    struct ContextClient: Encodable, Sendable {
        var clientName: String
        var clientVersion: String
        var osName: String?
        var osVersion: String?
        var deviceMake: String?
        var deviceModel: String?
        var gl: String
        var hl: String
        var visitorData: String?
    }

    func context(gl: String, hl: String, visitorData: String?, dataSyncId: String? = nil) -> InnerTubeContext {
        InnerTubeContext(
            client: ContextClient(
                clientName: clientName,
                clientVersion: clientVersion,
                osName: osName,
                osVersion: osVersion,
                deviceMake: deviceMake,
                deviceModel: deviceModel,
                gl: gl,
                hl: hl,
                visitorData: visitorData
            ),
            user: InnerTubeContext.User(onBehalfOfUser: dataSyncId)
        )
    }

    static let webRemix = InnerTubeClientDescriptor(
        clientName: "WEB_REMIX",
        clientVersion: "1.20260213.01.00",
        clientId: "67",
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
        osName: nil,
        osVersion: nil,
        deviceMake: nil,
        deviceModel: nil
    )

    static let ios = InnerTubeClientDescriptor(
        clientName: "IOS_MUSIC",
        clientVersion: "7.27.0",
        clientId: "26",
        userAgent: "com.google.ios.youtubemusic/7.27.0 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)",
        osName: "iOS",
        osVersion: "18.2.22C152",
        deviceMake: "Apple",
        deviceModel: "iPhone16,2"
    )

    static let androidVr = InnerTubeClientDescriptor(
        clientName: "ANDROID_VR",
        clientVersion: "1.43.32",
        clientId: "28",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)",
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3"
    )
}

struct PlayerPayload: Sendable {
    var videoId: String
    var title: String
    var author: String?
    var duration: TimeInterval?
    var thumbnails: [Thumbnail]
    var formats: [PlayerFormat]
    var playabilityStatus: String
    var reason: String?
    var hlsManifestURL: URL?
    var serverAbrStreamingURL: URL?

    var bestAudioURL: URL? {
        formats
            .filter { $0.url != nil && $0.mimeType.hasPrefix("audio/") }
            .sorted { lhs, rhs in
                let lhsScore = (lhs.mimeType.contains("mp4") ? 10_000_000 : 0) + lhs.bitrate
                let rhsScore = (rhs.mimeType.contains("mp4") ? 10_000_000 : 0) + rhs.bitrate
                return lhsScore > rhsScore
            }
            .first?
            .url
    }

    var preferredPlaybackURL: URL? {
        bestAudioURL ?? hlsManifestURL ?? serverAbrStreamingURL
    }
}

struct PlayerFormat: Sendable {
    var itag: Int
    var url: URL?
    var mimeType: String
    var bitrate: Int
    var contentLength: Int?
    var quality: String?
    var audioQuality: String?
}
