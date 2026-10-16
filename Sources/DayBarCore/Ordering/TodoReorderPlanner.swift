import Foundation

/// Plans a drag/keyboard move inside one visible list. The list may be a filtered slice of
/// the global order (a day, a project, a column): the task lands between its new visible
/// neighbours, which keeps every other view's relative order intact.
public enum TodoReorderPlanner {
    /// - Parameters:
    ///   - id: the moved task. It may be absent from `visible` (dropped in from elsewhere).
    ///   - index: insertion position in `visible` as displayed *before* the move (SwiftUI
    ///     `onMove` semantics: moving down past row `i` passes `i + 1`).
    ///   - visible: the list in display order; must be ascending by `sortOrder`.
    public static func placement(moving id: UUID, toIndex index: Int, within visible: [ReorderSlot]) -> ReorderPlacement {
        var others = visible
        var target = max(0, min(index, visible.count))
        if let source = visible.firstIndex(where: { $0.id == id }) {
            if target == source || target == source + 1 { return .unchanged }
            others.remove(at: source)
            if target > source { target -= 1 }
        }
        target = max(0, min(target, others.count))
        let lower = target > 0 ? others[target - 1].sortOrder : nil
        let upper = target < others.count ? others[target].sortOrder : nil
        if lower == nil && upper == nil { return .unchanged }
        guard let value = SortOrderMath.between(lower, upper) else { return .needsRenormalize }
        return .value(value)
    }

    /// `index` for moving the task `offset` rows up (negative) or down (positive) in
    /// `visible`, in `placement` semantics; `nil` when it can't move that way.
    public static func index(moving id: UUID, by offset: Int, within visible: [ReorderSlot]) -> Int? {
        guard let source = visible.firstIndex(where: { $0.id == id }), offset != 0 else { return nil }
        let destination = max(0, min(source + offset, visible.count - 1))
        guard destination != source else { return nil }
        return destination > source ? destination + 1 : destination
    }
}
