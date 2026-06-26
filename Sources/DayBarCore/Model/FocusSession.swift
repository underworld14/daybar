import Foundation
import SwiftData

/// A completed Pomodoro focus session, logged when a work phase ends. Powers the
/// focus-minutes analytics.
@Model
public final class FocusSession {
    @Attribute(.unique) public var id: UUID = UUID()
    public var endedAt: Date = Date.now
    public var minutes: Int = 0
    /// true = the focus phase finished naturally; false = skipped early.
    public var completed: Bool = false

    public init(id: UUID = UUID(), endedAt: Date = .now, minutes: Int = 0, completed: Bool = false) {
        self.id = id
        self.endedAt = endedAt
        self.minutes = minutes
        self.completed = completed
    }
}
