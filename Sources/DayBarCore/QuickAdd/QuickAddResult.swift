import Foundation

/// A parsed quick-add line: the clean title plus whatever the syntax set.
public struct QuickAddResult: Equatable, Sendable {
    public let title: String
    public let priority: Priority?
    public let day: QuickAddDay?
    public let projectID: UUID?
    /// Recognized tokens in typing order (last of each kind wins for the values above).
    public let tokens: [QuickAddToken]

    public init(title: String, priority: Priority?, day: QuickAddDay?, projectID: UUID?, tokens: [QuickAddToken]) {
        self.title = title
        self.priority = priority
        self.day = day
        self.projectID = projectID
        self.tokens = tokens
    }
}
