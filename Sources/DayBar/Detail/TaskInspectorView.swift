import SwiftUI
import DayBarCore

/// The main window's right-hand inspector: live details of the selected task. A task that
/// moves out of the current view (new date, other project) stays here, with a note and a
/// button to jump to where it now lives.
struct TaskInspectorView: View {
    var appState: AppState
    /// The board's scope: its memoized snapshot resolves the selection without a fetch.
    let scope: TaskScope?
    let selectedID: UUID?
    /// Switches the window to a scope (keeping the selection).
    var onReveal: (TaskScope) -> Void

    var body: some View {
        if let selectedID, let scope, let todo = resolve(selectedID, in: scope) {
            VStack(spacing: 0) {
                if appState.boardSnapshot(for: scope).byID[selectedID] == nil {
                    OutsideScopeNote(appState: appState, todo: todo, scope: scope, onReveal: onReveal)
                }
                TaskDetailForm(appState: appState, todo: todo)
                    .id(todo.id)
            }
        } else {
            ContentUnavailableView {
                Label("No Task Selected", systemImage: "sidebar.right")
            } description: {
                Text("Select a task to see and edit its details.")
            }
        }
    }

    private func resolve(_ id: UUID, in scope: TaskScope) -> DailyTodo? {
        appState.boardSnapshot(for: scope).byID[id] ?? appState.lookupTodo(id: id)
    }
}

/// "Planned for Tue 21 Oct, so it isn't in Today." + a button to that day's view.
private struct OutsideScopeNote: View {
    var appState: AppState
    let todo: DailyTodo
    let scope: TaskScope
    var onReveal: (TaskScope) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThemeMetrics.spacingM) {
            Image(systemName: "arrow.uturn.right.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(revealTitle) { onReveal(target) }
                .controlSize(.small)
        }
        .padding(.horizontal, ThemeMetrics.spacingL)
        .padding(.vertical, ThemeMetrics.spacingM)
        .background(ThemeColors.chipFill)
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        if case .project(let id) = scope, todo.projectID != id {
            return "This task is no longer in \(scopeName)."
        }
        let day = DayLabel.long(todo.plannedForDate, now: .now, calendar: appState.calendar)
        let when = day.detail == nil ? day.title : day.title.lowercased()
        return "Planned for \(when), so it isn't in \(scopeName)."
    }

    /// Where the task shows up now.
    private var target: TaskScope {
        let today = DayMath.startOfDay(.now, calendar: appState.calendar)
        let planned = DayMath.startOfDay(todo.plannedForDate, calendar: appState.calendar)
        if !todo.isCompleted {
            if planned == today { return .today }
            if planned == DayMath.nextDay(today, calendar: appState.calendar) { return .tomorrow }
        }
        if let projectID = todo.projectID, appState.projects.contains(where: { $0.id == projectID }) {
            return .project(projectID)
        }
        return .allTasks
    }

    private var revealTitle: String {
        switch target {
        case .today: return "Show in Today"
        case .tomorrow: return "Show in Tomorrow"
        case .allTasks: return "Show in All Tasks"
        case .project(let id): return "Show in \(appState.projects.first(where: { $0.id == id })?.name ?? "Project")"
        }
    }

    private var scopeName: String {
        switch scope {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .allTasks: return "All Tasks"
        case .project(let id): return appState.projects.first(where: { $0.id == id })?.name ?? "this project"
        }
    }
}
