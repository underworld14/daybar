import Foundation

/// Outcome of planning a move.
public enum ReorderPlacement: Equatable, Sendable {
    /// Write this `sortOrder` to the moved task.
    case value(Double)
    /// The task already sits there (or is alone).
    case unchanged
    /// Neighbours are too close (or equal); renormalize all orders and plan again.
    case needsRenormalize
}
