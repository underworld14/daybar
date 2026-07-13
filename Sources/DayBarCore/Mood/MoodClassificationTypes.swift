import Foundation

/// Whether an AI classification is trustworthy enough to apply without keyword fallback.
public enum MoodConfidence: Sendable, Equatable {
    case high
    case low
}

/// Raw output from Foundation Models guided generation.
public struct MoodAIClassification: Sendable, Equatable {
    public let tag: MoodTag
    /// Model self-reported certainty on a 1 (guess) – 5 (certain) scale.
    public let confidence: Int

    public init(tag: MoodTag, confidence: Int) {
        self.tag = tag
        self.confidence = confidence
    }
}

/// Final mood suggestion after AI classification and optional keyword fallback.
public struct MoodClassificationResult: Sendable, Equatable {
    public let tag: MoodTag
    public let source: MoodSource

    public init(tag: MoodTag, source: MoodSource) {
        self.tag = tag
        self.source = source
    }
}

/// Test seam around on-device classification.
public protocol MoodAIClassifying: Sendable {
    func classify(reflection: String) async throws -> MoodAIClassification
}
