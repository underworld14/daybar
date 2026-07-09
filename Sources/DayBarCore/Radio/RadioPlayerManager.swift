import Foundation
import AVFoundation
import Observation

/// Live SomaFM stream playback via AVPlayer with reconnect and persistence.
@MainActor
@Observable
public final class RadioPlayerManager {
    public private(set) var currentChannel: SomaFMChannel?
    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    public private(set) var isReconnecting = false
    public private(set) var playbackError: String?
    public private(set) var nowPlaying: String?
    public var volume: Float {
        get { player?.volume ?? Preferences.radioVolume }
        set {
            let clamped = min(max(newValue, 0), 1)
            player?.volume = clamped
            Preferences.radioVolume = clamped
        }
    }

    /// Fired whenever playback actually begins (any entry point: play, next/prev, retry,
    /// restore, reconnect). Lets a coordinator enforce mutual exclusion with other audio
    /// (the focus ticking sound) without every call site having to remember to do so.
    public var onPlaybackStarted: (() -> Void)?

    @ObservationIgnored private let service: SomaFMService
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var bufferObservation: NSKeyValueObservation?
    @ObservationIgnored private var failedObserver: NSObjectProtocol?
    @ObservationIgnored private var activityToken: (any NSObjectProtocol)?
    @ObservationIgnored private var reconnectAttempt = 0
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var nowPlayingTask: Task<Void, Never>?

    private let maxReconnectAttempts = 3
    private let reconnectBackoffs: [TimeInterval] = [2, 4, 8]

    public init(service: SomaFMService = SomaFMService()) {
        self.service = service
    }

    // MARK: - Controls

    public func play(channel: SomaFMChannel) async {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        isReconnecting = false
        await startPlayback(channel: channel, markUserStarted: true, userFacingErrors: true)
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        isBuffering = false
        isReconnecting = false
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        endActivity()
        stopNowPlayingRefresh()
        if let channel = currentChannel {
            persistSelection(channel: channel, wasPlaying: false, hasUserStarted: Preferences.radioHasUserStarted)
        }
    }

    public func stop() {
        pause()
        teardownPlayer()
        playbackError = nil
    }

    public func switchChannel(to channel: SomaFMChannel) async {
        await play(channel: channel)
    }

    public func togglePlayPause() async {
        if isPlaying {
            pause()
        } else if let channel = currentChannel {
            await play(channel: channel)
        }
    }

    public func playNextChannel(in channels: [SomaFMChannel]) async {
        guard let next = SomaFMCuratedChannels.adjacentChannel(
            from: currentChannel, in: channels, direction: .next
        ) else { return }
        await play(channel: next)
    }

    public func playPreviousChannel(in channels: [SomaFMChannel]) async {
        guard let previous = SomaFMCuratedChannels.adjacentChannel(
            from: currentChannel, in: channels, direction: .previous
        ) else { return }
        await play(channel: previous)
    }

    public func restoreSession(channels: [SomaFMChannel]) async {
        let id = Preferences.radioLastChannelID ?? SomaFMCuratedChannels.curatedSkipIDs.first
        if let id, let channel = channels.first(where: { $0.id == id }) {
            currentChannel = channel
            nowPlaying = channel.lastPlaying
        } else if let first = channels.first {
            currentChannel = first
            nowPlaying = first.lastPlaying
        }

        guard Preferences.radioHasUserStarted, Preferences.radioWasPlaying,
              let channel = currentChannel else { return }
        await play(channel: channel)
    }

    public func refreshNowPlaying(from channels: [SomaFMChannel]) {
        guard let id = currentChannel?.id,
              let updated = channels.first(where: { $0.id == id }) else { return }
        currentChannel = updated
        if let track = updated.lastPlaying, !track.isEmpty {
            nowPlaying = track
        }
    }

    public func retryPlayback() async {
        playbackError = nil
        if let channel = currentChannel {
            await play(channel: channel)
        }
    }

    // MARK: - Playback

    private func startPlayback(
        channel: SomaFMChannel,
        markUserStarted: Bool,
        userFacingErrors: Bool
    ) async {
        playbackError = nil
        currentChannel = channel
        nowPlaying = channel.lastPlaying
        isBuffering = true

        let hasUserStarted = markUserStarted ? true : Preferences.radioHasUserStarted
        persistSelection(channel: channel, wasPlaying: false, hasUserStarted: hasUserStarted)

        do {
            let streamURL = try await service.resolveStreamURL(for: channel)
            startPlayer(with: streamURL)
            player?.volume = Preferences.radioVolume
            isPlaying = true
            onPlaybackStarted?()
            reconnectAttempt = 0
            isReconnecting = false
            beginActivity()
            startNowPlayingRefresh()
            persistSelection(channel: channel, wasPlaying: true, hasUserStarted: hasUserStarted)
        } catch {
            isBuffering = false
            isReconnecting = false
            teardownPlayer()
            persistSelection(channel: channel, wasPlaying: false, hasUserStarted: hasUserStarted)
            if userFacingErrors {
                isPlaying = false
                playbackError = "Couldn't connect to \(channel.title). Tap play to retry."
                print("DayBar: radio play failed: \(error)")
            } else {
                scheduleReconnect()
            }
        }
    }

    private func reconnectPlay(channel: SomaFMChannel) async {
        await startPlayback(channel: channel, markUserStarted: false, userFacingErrors: false)
    }

    // MARK: - Player internals

    private func startPlayer(with url: URL) {
        teardownPlayerObservers()
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        player = newPlayer
        observePlayerItem(item)
        observeTimeControl(newPlayer)
        observeBuffering(item)
        observeFailure(for: item)
        newPlayer.play()
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleItemStatus(item.status)
            }
        }
    }

    private func observeTimeControl(_ player: AVPlayer) {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isBuffering = false
                    self.isReconnecting = false
                    self.playbackError = nil
                case .paused:
                    if !self.isReconnecting {
                        self.isBuffering = false
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    private func observeBuffering(_ item: AVPlayerItem) {
        bufferObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.isBuffering = !item.isPlaybackLikelyToKeepUp
            }
        }
    }

    private func observeFailure(for item: AVPlayerItem) {
        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
        }
        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleReconnect()
            }
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            if isPlaying { isBuffering = false }
        case .failed:
            scheduleReconnect()
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func scheduleReconnect() {
        guard isPlaying, let channel = currentChannel else { return }
        guard reconnectTask == nil else { return }
        guard reconnectAttempt < maxReconnectAttempts else {
            isReconnecting = false
            isBuffering = false
            playbackError = "Connection lost. Tap play to retry."
            pause()
            return
        }
        isReconnecting = true
        isBuffering = true
        playbackError = nil
        let delay = reconnectBackoffs[min(reconnectAttempt, reconnectBackoffs.count - 1)]
        reconnectAttempt += 1
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.isPlaying else { return }
            self.reconnectTask = nil
            await self.reconnectPlay(channel: channel)
        }
    }

    private func teardownPlayerObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        bufferObservation?.invalidate()
        bufferObservation = nil
        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
            self.failedObserver = nil
        }
    }

    private func teardownPlayer() {
        reconnectTask?.cancel()
        reconnectTask = nil
        player?.pause()
        teardownPlayerObservers()
        player = nil
    }

    private func beginActivity() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "DayBar radio playing"
        )
    }

    private func endActivity() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    // MARK: - Now playing poll

    private func startNowPlayingRefresh() {
        stopNowPlayingRefresh()
        nowPlayingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(90))
                guard let self, self.isPlaying, !Task.isCancelled else { break }
                if let channels = try? await self.service.fetchCuratedChannels() {
                    self.refreshNowPlaying(from: channels)
                }
            }
        }
    }

    private func stopNowPlayingRefresh() {
        nowPlayingTask?.cancel()
        nowPlayingTask = nil
    }

    // MARK: - Persistence

    private func persistSelection(channel: SomaFMChannel, wasPlaying: Bool, hasUserStarted: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(channel.id, forKey: PreferenceKeys.radioLastChannelID)
        defaults.set(wasPlaying, forKey: PreferenceKeys.radioWasPlaying)
        defaults.set(hasUserStarted, forKey: PreferenceKeys.radioHasUserStarted)
    }
}
