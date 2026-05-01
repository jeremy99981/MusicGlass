import AVFoundation

final class AudioSessionManager {
    func configure() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
    }

    func activate() throws {
        try configure()
        try AVAudioSession.sharedInstance().setActive(true)
    }
}
