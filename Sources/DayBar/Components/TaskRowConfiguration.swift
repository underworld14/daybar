import DayBarCore

/// Everything a task row displays, as plain values (no model or state access in the row).
struct TaskRowConfiguration {
    /// How the title responds to clicks: the board opens details; the tray renames on
    /// double-click.
    enum TitleInteraction {
        case openDetailsOnClick
        case renameOnDoubleClick
    }

    var title: String
    var status: TaskStatus
    var priority: Priority
    var isFromReminders = false
    var projectName: String?
    var projectSymbol: String?
    var dateLabel: String?
    var ageLabel: String?
    var ageTier: EscalationTier = .onPlan
    var hasNotes = false
    var checklist: ChecklistProgress?
    var isSelected = false
    var titleInteraction: TitleInteraction = .renameOnDoubleClick
}
