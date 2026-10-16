import DayBarCore

/// Intents a task row can trigger; the owner wires them to `AppState`.
struct TaskRowActions {
    var toggleComplete: () -> Void
    var toggleInProgress: () -> Void
    var setPriority: (Priority) -> Void
    var rename: ((String) -> Void)?
    var openDetails: (() -> Void)?
    /// Reports pointer hover so the owner can target keyboard shortcuts at this row.
    var hoverChanged: ((Bool) -> Void)?
}
