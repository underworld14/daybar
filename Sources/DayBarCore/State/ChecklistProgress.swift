import Foundation

/// Done/total checklist counts for one task, cached by `AppState` so rows never fetch.
public struct ChecklistProgress: Equatable, Sendable {
    public let done: Int
    public let total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    public var isEmpty: Bool { total == 0 }
}
