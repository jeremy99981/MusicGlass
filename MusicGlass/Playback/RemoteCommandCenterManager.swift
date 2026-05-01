import MediaPlayer

final class RemoteCommandCenterManager {
    private let commandCenter = MPRemoteCommandCenter.shared()

    func configure(
        play: @escaping @Sendable () -> Void,
        pause: @escaping @Sendable () -> Void,
        toggle: @escaping @Sendable () -> Void,
        next: @escaping @Sendable () -> Void,
        previous: @escaping @Sendable () -> Void,
        seek: @escaping @Sendable (TimeInterval) -> Void
    ) {
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true

        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        commandCenter.playCommand.addTarget { _ in play(); return .success }
        commandCenter.pauseCommand.addTarget { _ in pause(); return .success }
        commandCenter.togglePlayPauseCommand.addTarget { _ in toggle(); return .success }
        commandCenter.nextTrackCommand.addTarget { _ in next(); return .success }
        commandCenter.previousTrackCommand.addTarget { _ in previous(); return .success }
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            seek(event.positionTime)
            return .success
        }
    }
}
