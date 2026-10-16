import Foundation

/// A task's identity and current position in a visible, manually ordered list.
public struct ReorderSlot: Equatable, Sendable {
    public let id: UUID
    public let sortOrder: Double

    public init(id: UUID, sortOrder: Double) {
        self.id = id
        self.sortOrder = sortOrder
    }
}
