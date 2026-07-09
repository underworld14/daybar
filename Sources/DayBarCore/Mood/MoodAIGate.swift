import Foundation

/// Pure decision of whether the end-of-day review should attempt AI classification —
/// extracted out of the view so every branch is unit-testable without SwiftUI, a real
/// device, or `FoundationModels`.
public enum MoodAIGate {
    public static let minimumWordCount = 3

    /// - Parameter alreadyReviewed: true when a `DayLog` already exists for today (e.g. the
    ///   user reopened the sheet via "Review day…" after finishing it once). Consistent with
    ///   "1 entry = 1 day, immutable": a saved mood is never silently reclassified — the user
    ///   would have to change the reflection text and re-trigger manually in a future release.
    public static func shouldAttemptClassification(
        availability: MoodAIAvailability,
        aiEnabled: Bool,
        reflection: String,
        alreadyReviewed: Bool = false
    ) -> Bool {
        guard aiEnabled, !alreadyReviewed else { return false }
        guard availability == .available else { return false }
        return meaningfulUnitCount(in: reflection) >= minimumWordCount
    }

    private static func meaningfulUnitCount(in reflection: String) -> Int {
        let words = reflection.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        if words.count > 1 { return words.count }
        let trimmed = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard containsCJK(trimmed) else { return words.count }
        return trimmed.count
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }

    /// A late AI suggestion must never clobber a mood the user already picked by hand
    /// while it was in flight, nor apply after the surrounding task was cancelled
    /// (e.g. the reflection text changed again before this suggestion arrived).
    public static func shouldApplySuggestion(isCancelled: Bool, currentSource: MoodSource) -> Bool {
        !isCancelled && currentSource != .manual
    }
}
