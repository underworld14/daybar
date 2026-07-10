import Foundation

/// Pure decision of whether the end-of-day review should attempt AI classification —
/// extracted out of the view so every branch is unit-testable without SwiftUI, a real
/// device, or `FoundationModels`.
public enum MoodAIGate {
    public static let minimumWordCount = 3

    /// - Parameter alreadyReviewed: true when a `DayLog` already exists for today (e.g. the
    ///   user reopened the sheet via "Review day…" after finishing it once). Auto
    ///   re-classification is skipped unless `explicitRequest` is true or the reflection
    ///   text has changed from what was saved.
    /// - Parameter explicitRequest: true when the user tapped "Suggest mood again".
    public static func shouldAttemptClassification(
        availability: MoodAIAvailability,
        aiEnabled: Bool,
        reflection: String,
        alreadyReviewed: Bool = false,
        savedReflection: String? = nil,
        explicitRequest: Bool = false
    ) -> Bool {
        guard aiEnabled else { return false }
        if alreadyReviewed {
            let reflectionUnchanged = savedReflection.map { $0 == reflection } ?? true
            guard explicitRequest || !reflectionUnchanged else { return false }
        }
        guard availability == .available else { return false }
        return meaningfulUnitCount(in: reflection) >= minimumWordCount
    }

    /// Whether `reflection` is long enough for the AI to attempt a suggestion.
    public static func hasEnoughTextForClassification(_ reflection: String) -> Bool {
        meaningfulUnitCount(in: reflection) >= minimumWordCount
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
    /// for the *same* reflection text, nor apply after the surrounding task was cancelled
    /// (e.g. the reflection text changed again before this suggestion arrived). Editing
    /// the reflection clears the manual lock so a new suggestion can land.
    /// - Parameter explicitRequest: true when the user tapped "Suggest mood again" —
    ///   allows replacing a manual pick for the same reflection text.
    public static func shouldApplySuggestion(
        isCancelled: Bool,
        currentSource: MoodSource,
        reflectionAtManualPick: String? = nil,
        classifiedReflection: String,
        explicitRequest: Bool = false
    ) -> Bool {
        guard !isCancelled else { return false }
        guard currentSource == .manual else { return true }
        if explicitRequest { return true }
        guard let locked = reflectionAtManualPick else { return true }
        return locked != classifiedReflection
    }
}
