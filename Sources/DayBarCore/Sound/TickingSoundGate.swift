import Foundation

/// Pure rule for whether the ambient focus ticking sound should be playing — extracted so the
/// preference/phase combination is unit-testable without AVFoundation, mirroring `MoodAIGate`
/// and `EndOfDayReviewGate`.
public enum TickingSoundGate {
    /// Ticking runs only during an actively-counting-down work phase, and only when the user
    /// has opted in. Breaks, pauses, and the idle state are all silent.
    public static func shouldPlay(preferenceEnabled: Bool, isWorkPhase: Bool, isRunning: Bool) -> Bool {
        preferenceEnabled && isWorkPhase && isRunning
    }
}
