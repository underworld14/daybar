import Foundation
import DayBarCore

/// Turns a board composer line into a `TodoDraft`: quick-add syntax first, then the date
/// picked in the composer, then the scope's defaults (its day, its project).
@MainActor
enum BoardComposer {
    static func draft(
        from text: String,
        scope: TaskScope,
        column: BoardColumn,
        pickedDate: Date?,
        appState: AppState
    ) -> TodoDraft? {
        let projects = appState.projects.map { QuickAddParser.ProjectRef(id: $0.id, name: $0.name) }
        guard let parsed = QuickAddParser.parse(text, projects: projects) else { return nil }
        let calendar = appState.calendar
        let day: Date
        switch parsed.day {
        case .today?: day = DayMath.startOfDay(.now, calendar: calendar)
        case .tomorrow?: day = DayMath.nextDay(.now, calendar: calendar)
        case nil:
            day = pickedDate ?? (scope == .tomorrow
                ? DayMath.nextDay(.now, calendar: calendar)
                : DayMath.startOfDay(.now, calendar: calendar))
        }
        var projectID = parsed.projectID
        if projectID == nil, case .project(let id) = scope { projectID = id }
        return TodoDraft(
            title: parsed.title,
            priority: parsed.priority ?? .none,
            plannedFor: day,
            projectID: projectID,
            column: column
        )
    }
}
