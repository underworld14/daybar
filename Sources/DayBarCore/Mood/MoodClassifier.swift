import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)

/// On-device classification of a reflection into one `MoodTag`. The AI never produces the
/// score — it only ever picks a closed tag, and `MoodTag.score` is the single source of
/// truth for the numeric value (see `MoodTag`).
///
/// Uses Apple's [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
/// framework (`SystemLanguageModel`) — entirely on-device when Apple Intelligence is available.
@available(macOS 26.0, *)
public struct MoodClassifier: Sendable {
    public init() {}

    /// Constrained vocabulary via `@Guide(.anyOf)` so guided generation cannot emit free-form
    /// labels like "Happy" / "senang" that previously coerced to `.neutral`.
    @Generable
    struct Classification {
        @Guide(
            description: "Mood that best matches the writer's feelings",
            .anyOf([
                "lovestruck", "proud", "happy", "productive", "social", "neutral",
                "busyMeetings", "tired", "anxious", "stressed", "disappointed",
            ])
        )
        var tag: String

        @Guide(
            description: "How confident you are in this mood tag, 1 is a guess and 5 is certain",
            .range(1...5)
        )
        var confidence: Int
    }

    /// Classifies `text` via constrained decoding.
    ///
    /// Instructions stay English-only: Foundation Models can reject sessions whose
    /// instructions / schema text include unsupported locales (`unsupportedLanguageOrLocale`).
    public func classify(reflection text: String) async throws -> MoodAIClassification {
        let model = SystemLanguageModel(useCase: .contentTagging)
        let session = LanguageModelSession(model: model, instructions: """
            Classify a short daily journal reflection into exactly one mood tag from the schema.
            The reflection may be written in any language; map its meaning to the closest tag.
            Prefer a specific mood over neutral when sentiment is clear.
            Positive feelings map to happy, proud, lovestruck, productive, or social.
            Negative feelings map to disappointed, stressed, anxious, or tired.
            Set confidence to 1 when uncertain and 5 when the mood is obvious.
            """)
        let response = try await session.respond(
            to: text,
            generating: Classification.self
        )
        return MoodAIClassification(
            tag: MoodTag.fromAITag(response.content.tag),
            confidence: response.content.confidence
        )
    }
}

#else

/// Stub when the SDK has no Foundation Models (CI / older Xcode). Runtime never reaches
/// classification without `canImport(FoundationModels)` + Apple Intelligence.
@available(macOS 26.0, *)
public struct MoodClassifier: Sendable {
    public init() {}
    public func classify(reflection text: String) async throws -> MoodAIClassification {
        MoodAIClassification(tag: .neutral, confidence: 1)
    }
}

#endif
