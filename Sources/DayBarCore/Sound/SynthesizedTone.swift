import Foundation
import AVFoundation

/// Procedurally generates short PCM tones so alert sounds don't depend on a bundled
/// audio asset. A bell-like ring stacks a few harmonics with an exponential decay
/// envelope; a tick is a single short, sharply-decaying click.
public enum SynthesizedTone {
    private static let sampleRate: Double = 44_100

    /// A bell-like tone: a fundamental plus a couple of quieter overtones, all decaying
    /// exponentially, which reads as a soft "ring" rather than a flat sine beep.
    public static func bell(duration: TimeInterval = 0.9, fundamental: Double = 880) -> AVAudioPCMBuffer? {
        let overtones: [(multiplier: Double, gain: Float)] = [
            (1.0, 1.0),
            (2.01, 0.45),
            (3.0, 0.2),
        ]
        return makeBuffer(duration: duration) { t in
            var sample: Float = 0
            for (multiplier, gain) in overtones {
                sample += gain * Float(sin(2 * Double.pi * fundamental * multiplier * t))
            }
            let envelope = Float(exp(-3.2 * t))
            return sample * envelope * 0.5
        }
    }

    /// A very short, dry click that reads as a clock "tick" rather than a musical note.
    public static func tick(duration: TimeInterval = 0.05, frequency: Double = 1_800) -> AVAudioPCMBuffer? {
        makeBuffer(duration: duration) { t in
            let sample = Float(sin(2 * Double.pi * frequency * t))
            let envelope = Float(exp(-60 * t))
            return sample * envelope * 0.35
        }
    }

    /// Several bell strikes with a gap between each, baked into a single buffer so playback
    /// is just "schedule once and play" — no manual sequencing of multiple buffers needed.
    public static func ringSequence(
        strikes: Int = 3,
        strikeDuration: TimeInterval = 0.7,
        gap: TimeInterval = 0.35,
        fundamental: Double = 880
    ) -> AVAudioPCMBuffer? {
        guard strikes > 0 else { return nil }
        let overtones: [(multiplier: Double, gain: Float)] = [
            (1.0, 1.0),
            (2.01, 0.45),
            (3.0, 0.2),
        ]
        let cycle = strikeDuration + gap
        let totalDuration = TimeInterval(strikes) * cycle - gap
        return makeBuffer(duration: totalDuration) { t in
            let localT = t.truncatingRemainder(dividingBy: cycle)
            guard localT < strikeDuration else { return 0 }
            var sample: Float = 0
            for (multiplier, gain) in overtones {
                sample += gain * Float(sin(2 * Double.pi * fundamental * multiplier * localT))
            }
            let envelope = Float(exp(-3.2 * localT))
            return sample * envelope * 0.5
        }
    }

    /// A one-tick-per-`interval` buffer meant to be looped via `AVAudioPlayerNode`'s
    /// `.loops` option: the click sits at the very start, the rest of the buffer is silence,
    /// so looping it naturally produces a steady clock-like tick.
    public static func tickLoop(interval: TimeInterval = 1.0, clickDuration: TimeInterval = 0.05, frequency: Double = 1_800) -> AVAudioPCMBuffer? {
        makeBuffer(duration: interval) { t in
            guard t < clickDuration else { return 0 }
            let sample = Float(sin(2 * Double.pi * frequency * t))
            let envelope = Float(exp(-60 * t))
            return sample * envelope * 0.35
        }
    }

    private static func makeBuffer(
        duration: TimeInterval,
        amplitude: (Double) -> Float
    ) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            channel[frame] = amplitude(t)
        }
        return buffer
    }
}
