import AVFoundation
import Combine
import Foundation

@MainActor
protocol PlayerEngineProtocol: AnyObject {
    var state: PlayerState { get }
    var currentTrack: Track? { get }
    func play(_ track: Track, queue: [Track])
    func playRadio(from track: Track)
    func togglePlayPause()
    func next()
    func previous()
    func seek(to time: TimeInterval)
}

@MainActor
final class AVPlayerEngine: NSObject, ObservableObject, PlayerEngineProtocol {
    @Published private(set) var state: PlayerState = .idle
    @Published private(set) var currentTrack: Track?
    @Published private(set) var progress: TimeInterval = 0
    @Published private(set) var duration: TimeInterval?
    @Published private(set) var errorMessage: String?
    @Published private(set) var outputVolume: Float = 1
    @Published var queue = PlayerQueue()

    private let player = AVPlayer()
    private let youTubeMusicClient: YouTubeMusicClientProtocol
    private let historyRepository: HistoryRepository
    private let nowPlayingManager: NowPlayingManager
    private let remoteCommandCenterManager: RemoteCommandCenterManager
    private let audioSessionManager: AudioSessionManager
    private var timeObserver: Any?
    private var loadTask: Task<Void, Never>?
    private var playerStatusObservation: NSKeyValueObservation?
    private var playerRateObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var itemKeepUpObservation: NSKeyValueObservation?
    private var itemBufferEmptyObservation: NSKeyValueObservation?
    private var relatedQueueTask: Task<Void, Never>?
    private var lastLoggedProgressSecond = -1
    private let queueStorageKey = "MusicGlass.PlayerQueue"

    private struct PlaybackResolution {
        var track: Track
        var payload: PlayerPayload
        var streamURL: URL
    }

    init(
        youTubeMusicClient: YouTubeMusicClientProtocol,
        historyRepository: HistoryRepository,
        nowPlayingManager: NowPlayingManager,
        remoteCommandCenterManager: RemoteCommandCenterManager,
        audioSessionManager: AudioSessionManager
    ) {
        self.youTubeMusicClient = youTubeMusicClient
        self.historyRepository = historyRepository
        self.nowPlayingManager = nowPlayingManager
        self.remoteCommandCenterManager = remoteCommandCenterManager
        self.audioSessionManager = audioSessionManager
        super.init()
        restoreQueue()
        configureObservers()
        configureRemoteCommands()
        player.volume = outputVolume
    }

    func play(_ track: Track, queue tracks: [Track] = []) {
        queue.replace(with: tracks, startingAt: track)
        persistQueue()
        loadAndPlay(track)
    }

    func playRadio(from track: Track) {
        if let currentTrack, currentTrack.musicGlassIsSameQueueItem(as: track) {
            relatedQueueTask?.cancel()
            queue.replaceCurrentTrack(with: currentTrack)
            persistQueue()
            scheduleRelatedQueue(for: currentTrack, replaceUpcoming: true)
            updateNowPlaying()
            AppLogger.playback.notice("Refreshing radio queue without restarting \(currentTrack.videoId, privacy: .public)")
            return
        }

        queue.replace(with: [track], startingAt: track)
        persistQueue()
        loadAndPlay(track, replaceUpcomingWithRelated: true)
        AppLogger.playback.notice("Starting radio from \(track.videoId, privacy: .public)")
    }

    func togglePlayPause() {
        switch state {
        case .playing, .buffering:
            pause()
        case .paused:
            if let currentTrack {
                if player.currentItem == nil {
                    loadAndPlay(currentTrack)
                } else {
                    resume()
                }
            }
        case .idle, .failed:
            if let currentTrack {
                loadAndPlay(currentTrack)
            }
        case .loading:
            break
        }
    }

    func pause() {
        player.pause()
        state = .paused
        updateNowPlaying()
    }

    func resume() {
        do {
            try audioSessionManager.activate()
            player.play()
            state = .buffering
            updateNowPlaying()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func next() {
        if let currentTrack,
           let explicitNext = queue.upcomingTracks.first(where: { !$0.musicGlassIsSameQueueItem(as: currentTrack) }) {
            queue.setCurrent(explicitNext)
            persistQueue()
            loadAndPlay(explicitNext)
            return
        }

        guard let track = queue.nextTrack() else {
            pause()
            return
        }
        persistQueue()
        loadAndPlay(track)
    }

    func previous() {
        if progress > 5 {
            seek(to: 0)
            return
        }
        guard let track = queue.previousTrack() else {
            seek(to: 0)
            return
        }
        persistQueue()
        loadAndPlay(track)
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        progress = time
        updateNowPlaying()
    }

    func toggleShuffle() {
        queue.shuffleEnabled.toggle()
        persistQueue()
    }

    func cycleRepeatMode() {
        queue.repeatMode.advance()
        persistQueue()
    }

    func setVolume(to value: Float) {
        let clamped = min(max(value, 0), 1)
        outputVolume = clamped
        player.volume = clamped
    }

    func removeFromQueue(at offsets: IndexSet) {
        queue.remove(at: offsets)
        persistQueue()
    }

    func moveQueueItems(from offsets: IndexSet, to destination: Int) {
        queue.move(from: offsets, to: destination)
        persistQueue()
    }

    func removeUpcomingQueueItems(at offsets: IndexSet) {
        let startIndex = upcomingQueueStartIndex
        let mappedOffsets = IndexSet(offsets.map { $0 + startIndex })
        queue.remove(at: mappedOffsets)
        persistQueue()
    }

    func moveUpcomingQueueItems(from offsets: IndexSet, to destination: Int) {
        let startIndex = upcomingQueueStartIndex
        let mappedOffsets = IndexSet(offsets.map { $0 + startIndex })
        let mappedDestination = destination + startIndex
        queue.move(from: mappedOffsets, to: mappedDestination)
        persistQueue()
    }

    private func loadAndPlay(_ track: Track, replaceUpcomingWithRelated: Bool = false) {
        loadTask?.cancel()
        relatedQueueTask?.cancel()
        currentTrack = track
        queue.replaceCurrentTrack(with: track)
        persistQueue()
        progress = 0
        duration = track.duration
        errorMessage = nil
        state = .loading
        updateNowPlaying()

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolution = try await resolvePlayback(for: track)
                try Task.checkCancellation()
                let playbackTrack = resolution.track
                try audioSessionManager.activate()
                let asset = AVURLAsset(url: resolution.streamURL)
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = 1
                observeCurrentItem(item)
                player.replaceCurrentItem(with: item)
                player.automaticallyWaitsToMinimizeStalling = false
                currentTrack = playbackTrack
                queue.replaceCurrentTrack(with: playbackTrack)
                duration = resolution.payload.duration ?? playbackTrack.duration
                errorMessage = nil
                AppLogger.playback.notice("Loading stream for \(playbackTrack.videoId, privacy: .public) via \(resolution.streamURL.host ?? "unknown-host", privacy: .public)")
                player.play()
                state = .loading
                try? historyRepository.add(playbackTrack)
                persistQueue()
                scheduleRelatedQueue(for: playbackTrack, replaceUpcoming: replaceUpcomingWithRelated)
                updateNowPlaying()
            } catch is CancellationError {
                AppLogger.playback.notice("Playback load cancelled")
            } catch {
                let message = error.localizedDescription
                AppLogger.playback.error("Playback failed: \(message, privacy: .public)")
                errorMessage = message
                state = .failed(message)
                updateNowPlaying()
            }
        }
    }

    private func resolvePlayback(for track: Track, allowFallback: Bool = true) async throws -> PlaybackResolution {
        let payload = try await youTubeMusicClient.getPlayer(videoId: track.videoId)
        if payload.playabilityStatus == "OK", let streamURL = payload.preferredPlaybackURL {
            let playbackTrack = enrichedTrack(from: track, payload: payload)
            return PlaybackResolution(track: playbackTrack, payload: payload, streamURL: streamURL)
        }

        let message = payload.reason ?? "Ce morceau ne peut pas être lu."
        guard allowFallback, let fallback = await playableFallbackTrack(for: track) else {
            throw AppError.streamUnavailable(message)
        }

        AppLogger.playback.notice("Fallback playback resolved \(track.videoId, privacy: .public) -> \(fallback.videoId, privacy: .public)")
        return try await resolvePlayback(for: fallback, allowFallback: false)
    }

    private func playableFallbackTrack(for track: Track) async -> Track? {
        let artistLine = track.artistLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle = track.title.musicGlassTitleWithoutParenthetical
        let queries = [
            "\(track.title) \(artistLine)",
            "\(baseTitle) \(artistLine)"
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()

        for query in queries {
            guard let result = try? await youTubeMusicClient.search(query: query, filter: .songs) else { continue }
            let candidates = (result.tracks + result.videos)
                .filter { $0.videoId != track.videoId }
                .filter { $0.musicGlassLooksLikeSameSong(as: track) }
                .prefix(6)

            for candidate in candidates {
                guard let payload = try? await youTubeMusicClient.getPlayer(videoId: candidate.videoId),
                      payload.playabilityStatus == "OK",
                      payload.preferredPlaybackURL != nil
                else { continue }
                return enrichedTrack(from: candidate, payload: payload)
            }
        }

        return nil
    }

    private func scheduleRelatedQueue(for track: Track, replaceUpcoming: Bool = false) {
        relatedQueueTask?.cancel()
        relatedQueueTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(450))
                let relatedTracks = await relatedTracks(for: track)
                try Task.checkCancellation()
                guard let currentTrack, currentTrack.musicGlassIsSameQueueItem(as: track) else { return }
                if replaceUpcoming {
                    queue.replaceUpcomingTracks(with: relatedTracks)
                } else {
                    queue.appendRelatedTracks(relatedTracks)
                }
                persistQueue()
                AppLogger.playback.notice("\(replaceUpcoming ? "Replaced upcoming queue with" : "Added", privacy: .public) \(relatedTracks.count, privacy: .public) related tracks")
            } catch is CancellationError {
                AppLogger.playback.notice("Related queue generation cancelled")
            } catch {
                AppLogger.playback.notice("Related queue generation skipped")
            }
        }
    }

    private func relatedTracks(for track: Track) async -> [Track] {
        if let nextTracks = try? await youTubeMusicClient.getRelatedTracks(videoId: track.videoId) {
            let filteredNextTracks = nextTracks
                .filter { $0.musicGlassIsQueueRecommendation(seed: track) }
                .uniquedBy(\.id)
            if filteredNextTracks.count >= 6 {
                return Array(filteredNextTracks.prefix(24))
            }
        }

        let queries = relatedQueries(for: track)
        guard !queries.isEmpty else { return [] }

        let client = youTubeMusicClient
        let seedArtistIds = Set(track.artists.map { $0.name.musicGlassQueueNormalized }.filter { !$0.isEmpty })

        let results = await withTaskGroup(of: [Track].self) { group in
            for query in queries {
                group.addTask {
                    guard let result = try? await client.search(query: query, filter: .songs) else { return [] }
                    return result.tracks + result.videos
                }
            }

            var tracks: [Track] = []
            for await result in group {
                tracks.append(contentsOf: result)
            }
            return tracks
        }

        let uniqueTracks = results
            .filter { $0.id != track.id && $0.musicGlassIsQueueRecommendation(seed: track) }
            .uniquedBy(\.id)

        let differentArtists = uniqueTracks.filter { candidate in
            let artists = Set(candidate.artists.map { $0.name.musicGlassQueueNormalized }.filter { !$0.isEmpty })
            guard !artists.isEmpty, !seedArtistIds.isEmpty else { return true }
            return artists.isDisjoint(with: seedArtistIds)
        }
        let sameArtists = uniqueTracks.filter { !differentArtists.contains($0) }

        return Array((differentArtists + sameArtists).prefix(24))
    }

    private func relatedQueries(for track: Track) -> [String] {
        let artists = track.artists.map(\.name).filter { !$0.isEmpty }
        let primaryArtist = artists.first ?? track.artistLine
        let listeningText = ([track.title, track.artistLine, track.album?.title ?? ""] + artists)
            .joined(separator: " ")
            .musicGlassQueueNormalized

        var queries: [String] = []
        if !primaryArtist.isEmpty {
            queries.append("\(primaryArtist) radio")
            queries.append("\(primaryArtist) artistes similaires")
        }

        if listeningText.containsAny(["plk", "ninho", "pnl", "jul", "damso", "nekfeu", "laylow", "tiakola", "gazo", "zola", "niska", "koba", "hamza", "leto", "sdm", "rap"]) {
            queries.append("rap français nouveautés")
            queries.append("\(primaryArtist) rap français similaires")
        } else if listeningText.containsAny(["rnb", "r&b", "sza", "the weeknd", "hamza", "soul"]) {
            queries.append("rnb chill nouveautés")
        } else if listeningText.containsAny(["electro", "house", "techno", "dance"]) {
            queries.append("electro house nouveautés")
        } else if listeningText.containsAny(["rock", "indie", "alternative", "twenty one pilots", "coldplay"]) {
            queries.append("rock alternatif nouveautés")
        } else if listeningText.containsAny(["chill", "lofi", "lo-fi", "piano", "calme"]) {
            queries.append("chill lofi playlist")
        }

        return queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    private func configureObservers() {
        playerStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.handleTimeControlStatus(player.timeControlStatus, reason: player.reasonForWaitingToPlay)
            }
        }

        playerRateObservation = player.observe(\.rate, options: [.initial, .new]) { player, _ in
            AppLogger.playback.notice("AVPlayer rate changed: \(player.rate, privacy: .public)")
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.progress = seconds
                    let isAdvancing = self.player.rate > 0 && self.player.timeControlStatus == .playing
                    if seconds > 0, isAdvancing, self.state != .playing {
                        self.state = .playing
                    }
                    self.logPlaybackProgressIfNeeded(seconds)

                    // Auto-next: if we know the real track duration and playback has reached it,
                    // skip to next immediately instead of waiting for AVPlayer's (wrong) end signal
                    if let knownDuration = self.currentTrack?.duration,
                       knownDuration > 0,
                       seconds >= knownDuration - 1.0,
                       isAdvancing {
                        AppLogger.playback.notice("Track reached known duration (\(knownDuration, privacy: .public)s), advancing to next")
                        self.playerItemDidEnd()
                        return
                    }
                }
                let itemDuration = self.player.currentItem?.duration.seconds
                if let itemDuration, itemDuration.isFinite, itemDuration > 0 {
                    let trackHasDuration = (self.currentTrack?.duration ?? 0) > 0
                    if !trackHasDuration {
                        self.duration = itemDuration
                    }
                }
                self.updateNowPlaying()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlayToEnd),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemPlaybackStalled),
            name: .AVPlayerItemPlaybackStalled,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioSessionInterrupted),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    private func observeCurrentItem(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleItemStatus(item.status, error: item.error)
            }
        }
        itemKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleLikelyToKeepUp(item.isPlaybackLikelyToKeepUp)
            }
        }
        itemBufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleBufferEmpty(item.isPlaybackBufferEmpty)
            }
        }
    }

    private func configureRemoteCommands() {
        remoteCommandCenterManager.configure(
            play: { [weak self] in Task { @MainActor in self?.resume() } },
            pause: { [weak self] in Task { @MainActor in self?.pause() } },
            toggle: { [weak self] in Task { @MainActor in self?.togglePlayPause() } },
            next: { [weak self] in Task { @MainActor in self?.next() } },
            previous: { [weak self] in Task { @MainActor in self?.previous() } },
            seek: { [weak self] time in Task { @MainActor in self?.seek(to: time) } }
        )
    }

    @objc private func playerItemDidEnd() {
        if queue.repeatMode == .one {
            seek(to: 0)
            resume()
        } else {
            next()
        }
    }

    @objc private func playerItemFailedToPlayToEnd(_ notification: Notification) {
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        let message = error?.localizedDescription ?? "La lecture a échoué avant la fin du morceau."
        AppLogger.playback.error("AVPlayer item failed: \(message, privacy: .public)")
        errorMessage = message
        state = .failed(message)
        updateNowPlaying()
    }

    @objc private func playerItemPlaybackStalled() {
        guard state != .paused, player.rate > 0 else { return }
        state = .buffering
        updateNowPlaying()
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus, reason: AVPlayer.WaitingReason?) {
        switch status {
        case .paused:
            if state == .loading || state == .buffering {
                return
            }
            if currentTrack != nil {
                state = .paused
            }
        case .waitingToPlayAtSpecifiedRate:
            if state != .paused {
                state = .buffering
            }
        case .playing:
            state = .playing
        @unknown default:
            break
        }
        if let reason {
            AppLogger.playback.notice("AVPlayer waiting reason: \(reason.rawValue, privacy: .public)")
        }
        updateNowPlaying()
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, error: Error?) {
        switch status {
        case .unknown:
            state = .loading
        case .readyToPlay:
            if let itemDuration = player.currentItem?.duration.seconds,
               itemDuration.isFinite,
               itemDuration > 0 {
                let trackHasDuration = (currentTrack?.duration ?? 0) > 0
                if !trackHasDuration {
                    duration = itemDuration
                }
            }
        case .failed:
            let message = error?.localizedDescription ?? player.currentItem?.error?.localizedDescription ?? "Le flux n’a pas pu être chargé."
            AppLogger.playback.error("AVPlayer item status failed: \(message, privacy: .public)")
            errorMessage = message
            state = .failed(message)
        @unknown default:
            break
        }
        updateNowPlaying()
    }

    private func handleLikelyToKeepUp(_ isLikelyToKeepUp: Bool) {
        guard isLikelyToKeepUp, player.rate > 0 else { return }
        state = .playing
        updateNowPlaying()
    }

    private func handleBufferEmpty(_ isBufferEmpty: Bool) {
        guard isBufferEmpty else { return }
        guard state != .paused, player.rate > 0 else { return }
        state = .buffering
        updateNowPlaying()
    }

    @objc private func audioSessionInterrupted(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }
        if type == .began {
            pause()
        }
    }

    @objc private func audioRouteChanged(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        else { return }
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }

    private func updateNowPlaying() {
        nowPlayingManager.update(track: currentTrack, state: state, elapsed: progress, duration: duration)
    }

    private var upcomingQueueStartIndex: Int {
        let currentIndex = queue.currentIndex ?? -1
        let start = currentIndex + 1
        return min(max(start, 0), queue.tracks.count)
    }

    private func logPlaybackProgressIfNeeded(_ seconds: TimeInterval) {
        let wholeSeconds = Int(seconds.rounded(.down))
        guard wholeSeconds >= 0,
              wholeSeconds != lastLoggedProgressSecond,
              wholeSeconds.isMultiple(of: 5)
        else { return }
        lastLoggedProgressSecond = wholeSeconds
        AppLogger.playback.notice("Playback progress: \(wholeSeconds, privacy: .public)s")
    }

    private func enrichedTrack(from track: Track, payload: PlayerPayload) -> Track {
        var enriched = track
        if enriched.artists.isEmpty, let author = payload.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            enriched.artists = [Artist(id: author.lowercased(), name: author)]
        }
        if let payloadDuration = payload.duration {
            enriched.duration = payloadDuration
        }
        if !payload.thumbnails.isEmpty {
            enriched.thumbnails = (enriched.thumbnails + payload.thumbnails).uniquedBy(\.url)
        }
        return enriched
    }

    private func persistQueue() {
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: queueStorageKey)
        }
    }

    private func restoreQueue() {
        guard let data = UserDefaults.standard.data(forKey: queueStorageKey),
              let restored = try? JSONDecoder().decode(PlayerQueue.self, from: data)
        else { return }
        queue = restored
        currentTrack = restored.currentTrack
    }
}

private extension String {
    var musicGlassQueueNormalized: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var musicGlassTitleWithoutParenthetical: String {
        replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func containsAny(_ values: [String]) -> Bool {
        values.contains { contains($0) }
    }

    var musicGlassHasBlockedQueueSignal: Bool {
        contains("podcast") ||
            contains("episode") ||
            contains("audiobook") ||
            contains("livre audio") ||
            contains("interview") ||
            contains("documentaire") ||
            contains("documentary") ||
            contains("reaction") ||
            contains("1 hour") ||
            contains("2 hour") ||
            contains("3 hour") ||
            contains("1h") ||
            contains("2h") ||
            contains("3h") ||
            contains("heure") ||
            contains("full album") ||
            contains("album complet") ||
            contains("compilation") ||
            contains("megamix") ||
            contains("mega mix") ||
            contains("non stop") ||
            contains("24/7") ||
            contains("top 100") ||
            contains("top 50")
    }
}

private extension Track {
    func musicGlassIsSameQueueItem(as other: Track) -> Bool {
        if videoId == other.videoId || id == other.id {
            return true
        }
        let lhsTitle = title.musicGlassQueueNormalized
        let rhsTitle = other.title.musicGlassQueueNormalized
        let lhsArtist = artistLine.musicGlassQueueNormalized
        let rhsArtist = other.artistLine.musicGlassQueueNormalized
        return !lhsTitle.isEmpty && !lhsArtist.isEmpty && lhsTitle == rhsTitle && lhsArtist == rhsArtist
    }

    func musicGlassIsQueueRecommendation(seed: Track) -> Bool {
        guard id != seed.id, videoId != seed.videoId else { return false }
        let folded = ([title, artistLine, album?.title ?? ""]).joined(separator: " ").musicGlassQueueNormalized
        guard !folded.isEmpty, !folded.musicGlassHasBlockedQueueSignal else { return false }
        guard !artistLine.musicGlassQueueNormalized.isEmpty else { return false }
        if let duration {
            return duration >= 25 && duration <= 12 * 60
        }
        return false
    }

    func musicGlassLooksLikeSameSong(as original: Track) -> Bool {
        let candidateTitle = title.musicGlassTitleWithoutParenthetical.musicGlassQueueNormalized
        let originalTitle = original.title.musicGlassTitleWithoutParenthetical.musicGlassQueueNormalized
        guard !candidateTitle.isEmpty, !originalTitle.isEmpty else { return false }
        guard candidateTitle == originalTitle || candidateTitle.contains(originalTitle) || originalTitle.contains(candidateTitle) else {
            return false
        }

        let originalArtists = Set(original.artistLine.musicGlassQueueNormalized
            .components(separatedBy: CharacterSet(charactersIn: ",&"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        guard !originalArtists.isEmpty else { return true }

        let candidateLine = artistLine.musicGlassQueueNormalized
        guard !candidateLine.isEmpty else { return false }
        return originalArtists.contains { candidateLine.contains($0) || $0.contains(candidateLine) }
    }
}
