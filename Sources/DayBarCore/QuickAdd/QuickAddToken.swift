import Foundation

/// A recognized piece of quick-add syntax, for the live preview chips.
public struct QuickAddToken: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case priority(Priority)
        case day(QuickAddDay)
        case project(id: UUID, name: String)
    }

    public let kind: Kind
    /// The text as typed (e.g. "!!", "besok", "#client").
    public let source: String

    public init(kind: Kind, source: String) {
        self.kind = kind
        self.source = source
    }
}

/// Days the quick-add syntax understands.
public enum QuickAddDay: Equatable, Sendable {
    case today, tomorrow
}
