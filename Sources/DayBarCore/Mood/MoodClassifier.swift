import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)

/// On-device classification of a reflection into one `MoodTag`. The AI never produces the
/// score — it only ever picks a `rawValue` from the closed list, and `MoodTag.score` is the
/// single source of truth for the numeric value (see `MoodTag`).
///
/// Uses Apple's [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
/// framework (`SystemLanguageModel`) — entirely on-device when Apple Intelligence is available.
@available(macOS 26.0, *)
public struct MoodClassifier: Sendable {
    public init() {}

    @Generable
    struct Classification {
        @Guide(description: "One of: lovestruck, proud, happy, productive, social, neutral, busyMeetings, tired, anxious, stressed, disappointed")
        var tag: String
    }

    /// Classifies `text` into one `MoodTag`. Falls back to `.neutral` if the model somehow
    /// returns a string outside the closed vocabulary.
    public func classify(reflection text: String) async throws -> MoodTag {
        let model = SystemLanguageModel(useCase: .contentTagging)
        let session = LanguageModelSession(model: model, instructions: """
            You classify a short daily journal reflection into exactly one mood tag
            from the provided list. The reflection may be written in any language.
            Do not add commentary — return only the tag that best matches the text.
            """)
        let response = try await session.respond(to: text, generating: Classification.self)
        return MoodTag(rawValue: response.content.tag) ?? .neutral
    }
}

/// Races `MoodClassifier.classify` against a timeout so the review sheet never hangs
/// waiting on the model. Returns `nil` on timeout, cancellation, or any classification
/// error — callers treat that identically to "AI declined to suggest", falling back to
/// the manual picker.
@available(macOS 26.0, *)
public func classifyMoodWithTimeout(_ text: String, seconds: Double = 3) async -> MoodTag? {
    try? await withThrowingTaskGroup(of: MoodTag?.self) { group in
        group.addTask { try await MoodClassifier().classify(reflection: text) }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            return nil
        }
        defer { group.cancelAll() }
        return try await group.next() ?? nil
    }.flatMap { $0 }
}

#else

/// Stub when the SDK has no Foundation Models (CI / older Xcode). Runtime never reaches
/// classification without `canImport(FoundationModels)` + Apple Intelligence.
@available(macOS 26.0, *)
public struct MoodClassifier: Sendable {
    public init() {}
    public func classify(reflection text: String) async throws -> MoodTag { .neutral }
}

@available(macOS 26.0, *)
public func classifyMoodWithTimeout(_ text: String, seconds: Double = 3) async -> MoodTag? {
    nil
}

#endif
