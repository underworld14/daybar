import Foundation

/// Our own mirror of `SystemLanguageModel.Availability`, decoupled from `FoundationModels`
/// so this type (and anything that consumes it) can be unit-tested on any macOS version
/// without importing `FoundationModels` or needing an Apple-Intelligence-eligible Mac.
public enum MoodAIAvailability: Equatable, Sendable {
    case available
    case unavailable(MoodAIUnavailableReason)
}

public enum MoodAIUnavailableReason: Equatable, Sendable {
    /// Host OS predates macOS 26 — `FoundationModels` doesn't exist there at all.
    case osTooOld
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case other
}

/// Injectable check for whether on-device mood classification can run right now.
/// Kept as a protocol (rather than calling `SystemLanguageModel.default` directly from
/// the UI) so tests can simulate every state without a real device.
public protocol MoodAIAvailabilityChecking: Sendable {
    var availability: MoodAIAvailability { get }
}
