import Foundation

/// AI-first mood classification with confidence assessment and keyword fallback.
public enum MoodClassificationPipeline: Sendable {
    /// Resolves the final suggestion from an AI result (or failure) and reflection text.
    public static func resolve(
        ai: MoodAIClassification?,
        reflection: String,
        aiFailed: Bool
    ) -> MoodClassificationResult? {
        if let ai, !aiFailed {
            let confidence = MoodConfidenceAssessor.assess(
                aiTag: ai.tag,
                aiConfidence: ai.confidence,
                reflection: reflection
            )
            if confidence == .high {
                return MoodClassificationResult(tag: ai.tag, source: .ai)
            }
            if let heuristic = MoodKeywordHeuristic.classify(reflection) {
                return MoodClassificationResult(tag: heuristic, source: .heuristic)
            }
            return MoodClassificationResult(tag: ai.tag, source: .ai)
        }

        if let heuristic = MoodKeywordHeuristic.classify(reflection) {
            return MoodClassificationResult(tag: heuristic, source: .heuristic)
        }
        return nil
    }
}

private struct MoodClassifyTimeout: Error {}

#if canImport(FoundationModels)

@available(macOS 26.0, *)
extension MoodClassifier: MoodAIClassifying {}

@available(macOS 26.0, *)
public func classifyMood(
    _ text: String,
    seconds: Double = 8,
    classifier: any MoodAIClassifying = MoodClassifier()
) async -> MoodClassificationResult? {
    let ai: MoodAIClassification?
    let aiFailed: Bool
    do {
        ai = try await withThrowingTaskGroup(of: MoodAIClassification.self) { group in
            group.addTask { try await classifier.classify(reflection: text) }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw MoodClassifyTimeout()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
        aiFailed = false
    } catch is MoodClassifyTimeout {
        print("DayBar: mood classify timed out after \(seconds)s")
        ai = nil
        aiFailed = true
    } catch {
        print("DayBar: mood classify failed: \(error)")
        ai = nil
        aiFailed = true
    }
    return MoodClassificationPipeline.resolve(ai: ai, reflection: text, aiFailed: aiFailed)
}

@available(macOS 26.0, *)
public func classifyMoodWithTimeout(_ text: String, seconds: Double = 8) async -> MoodTag? {
    await classifyMood(text, seconds: seconds)?.tag
}

#else

@available(macOS 26.0, *)
public func classifyMood(_ text: String, seconds: Double = 8) async -> MoodClassificationResult? {
    MoodClassificationPipeline.resolve(ai: nil, reflection: text, aiFailed: true)
}

@available(macOS 26.0, *)
public func classifyMoodWithTimeout(_ text: String, seconds: Double = 8) async -> MoodTag? {
    await classifyMood(text, seconds: seconds)?.tag
}

#endif
