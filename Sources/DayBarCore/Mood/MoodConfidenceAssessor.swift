import Foundation

/// Pure plausibility checks for an AI mood tag — unit-testable without Foundation Models.
public enum MoodConfidenceAssessor: Sendable {
    public static let lowSelfReportThreshold = 2

    /// Returns `.low` when the AI result should not be trusted over keyword fallback.
    public static func assess(
        aiTag: MoodTag,
        aiConfidence: Int,
        reflection: String
    ) -> MoodConfidence {
        if aiConfidence <= lowSelfReportThreshold { return .low }

        guard let heuristic = MoodKeywordHeuristic.classify(reflection) else {
            return .high
        }

        if aiTag == .neutral { return .low }

        if polarityBucket(for: aiTag) != polarityBucket(for: heuristic) {
            return .low
        }

        return .high
    }

    /// Positive / neutral / negative bucket derived from `MoodTag.score`.
    private static func polarityBucket(for tag: MoodTag) -> Int {
        let score = tag.score
        if score > 0 { return 1 }
        if score < 0 { return -1 }
        return 0
    }
}
