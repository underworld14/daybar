import Foundation
import DayBarCore

extension TaskRowConfiguration {
    /// Builds a row/card configuration from a task. Which metadata shows is per surface:
    /// the tray shows age, the board shows project and date chips.
    @MainActor
    static func make(
        _ todo: DailyTodo,
        appState: AppState,
        showsProject: Bool = false,
        showsDate: Bool = false,
        showsAge: Bool = false,
        isSelected: Bool = false,
        titleInteraction: TitleInteraction = .renameOnDoubleClick
    ) -> TaskRowConfiguration {
        let project = showsProject ? appState.project(for: todo) : nil
        let age = showsAge ? todo.ageLabel(calendar: appState.calendar) : nil
        return TaskRowConfiguration(
            title: todo.title,
            status: TaskStatus(todo),
            priority: todo.priority,
            isFromReminders: todo.source == .reminders,
            projectName: project?.name,
            projectSymbol: project?.symbolName,
            dateLabel: showsDate ? DayLabel.relative(todo.plannedForDate, now: .now, calendar: appState.calendar) : nil,
            ageLabel: age,
            ageTier: age == nil ? .onPlan : todo.escalationTier(thresholds: appState.thresholds, calendar: appState.calendar),
            hasNotes: todo.hasNotes,
            checklist: appState.checklistProgress[todo.id],
            isSelected: isSelected,
            titleInteraction: titleInteraction
        )
    }
}

extension TaskRowActions {
    /// Standard wiring of row/card intents to `AppState`.
    @MainActor
    static func make(
        _ todo: DailyTodo,
        appState: AppState,
        allowsRename: Bool = true,
        openDetails: (() -> Void)?
    ) -> TaskRowActions {
        TaskRowActions(
            toggleComplete: { withThemeAnimation(.reorder) { appState.toggleComplete(todo) } },
            toggleInProgress: { withThemeAnimation(.reorder) { appState.toggleInProgress(todo) } },
            setPriority: { level in withThemeAnimation(.reorder) { appState.setPriority(todo, level) } },
            rename: allowsRename ? { appState.rename(todo, to: $0) } : nil,
            openDetails: openDetails
        )
    }
}
