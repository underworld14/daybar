import Foundation
import AVFoundation

/// Loops a synthesized clock tick once per second, meant to run only while a focus
/// session is actively counting down. Cheap to start/stop repeatedly since the engine is
/// torn down whenever ticking isn't active.
@MainActor
public final class TickingSoundPlayer {
    public static let shared = TickingSoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isAttached = false
    public private(set) var isActive = false

    public init() {}

    public func start() {
        guard !isActive else { return }
        guard let buffer = SynthesizedTone.tickLoop() else { return }
        setUpIfNeeded(format: buffer.format)
        do {
            try engine.start()
        } catch {
            print("DayBar: ticking sound engine failed to start: \(error)")
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        isActive = true
    }

    public func stop() {
        guard isActive else { return }
        player.stop()
        engine.stop()
        isActive = false
    }

    private func setUpIfNeeded(format: AVAudioFormat) {
        guard !isAttached else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        isAttached = true
    }
}
