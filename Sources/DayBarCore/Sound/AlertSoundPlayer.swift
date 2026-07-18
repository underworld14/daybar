import Foundation
import AVFoundation

/// Plays the Pomodoro phase-end alert: a synthesized "ring" struck a few times, loud and
/// distinct enough to notice during focused work — unlike the short, quiet system sounds
/// this replaces. The engine is started lazily and torn down between plays so an idle
/// DayBar has no background audio hardware held open.
@MainActor
public final class AlertSoundPlayer {
    public static let shared = AlertSoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isAttached = false

    public init() {}

    public func playPhaseEndRing() {
        guard let buffer = SynthesizedTone.ringSequence() else { return }
        play(buffer)
    }

    /// Used by the Settings "Test sound" button.
    public func playTestRing() { playPhaseEndRing() }

    /// Soft garden growth / harvest chime (quieter than phase-end).
    public func playGardenChime() {
        guard let buffer = SynthesizedTone.gardenChime() else { return }
        play(buffer)
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        setUpIfNeeded(format: buffer.format)
        // Restart cleanly if a previous ring is somehow still playing, so back-to-back
        // triggers don't pile buffers up on the node.
        if player.isPlaying { player.stop() }
        do {
            try engine.start()
        } catch {
            print("DayBar: alert sound engine failed to start: \(error)")
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.stopIfIdle() }
        }
        player.play()
    }

    private func setUpIfNeeded(format: AVAudioFormat) {
        guard !isAttached else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        isAttached = true
    }

    private func stopIfIdle() {
        guard !player.isPlaying else { return }
        engine.stop()
    }
}
