import Foundation

/// Pure mapping between `ReminderDTO` and `DailyTodo`.
public enum ReminderMapping {
    public static func plannedDay(for dto: ReminderDTO, today: Date, calendar: Calendar) -> Date {
        if let due = dto.dueDate {
            return calendar.startOfDay(for: due)
        }
        return calendar.startOfDay(for: today)
    }

    public static func apply(_ dto: ReminderDTO, to todo: DailyTodo, today: Date, calendar: Calendar) {
        // Locally dropped items stay dropped until push completes; don't reopen from stale remote.
        if todo.status == .dropped, !dto.isCompleted {
            todo.title = dto.title
            todo.notes = dto.notes
            todo.externalModifiedAt = dto.modifiedAt
            return
        }

        let planned = plannedDay(for: dto, today: today, calendar: calendar)
        todo.title = dto.title
        todo.notes = dto.notes
        todo.dueDate = dto.dueDate
        todo.plannedForDate = planned
        if todo.originalPlannedDate > planned {
            todo.originalPlannedDate = planned
        }
        todo.priority = dto.priority
        todo.source = .reminders
        todo.externalIdentifier = dto.externalIdentifier
        todo.externalModifiedAt = dto.modifiedAt
        if dto.isCompleted {
            todo.completedDate = dto.completionDate ?? todo.completedDate ?? today
            todo.status = .completed
        } else if todo.status == .completed || todo.status == .dropped {
            todo.completedDate = nil
            todo.status = planned < calendar.startOfDay(for: today) ? .carriedOver : .planned
        } else if todo.status == .inProgress {
            // Keep in-progress; metadata already applied above.
        }
    }

    public static func makeTodo(from dto: ReminderDTO, today: Date, calendar: Calendar) -> DailyTodo {
        let planned = plannedDay(for: dto, today: today, calendar: calendar)
        let status: TodoStatus
        let completedDate: Date?
        if dto.isCompleted {
            status = .completed
            completedDate = dto.completionDate ?? today
        } else if planned < calendar.startOfDay(for: today) {
            status = .carriedOver
            completedDate = nil
        } else {
            status = .planned
            completedDate = nil
        }
        let todo = DailyTodo(
            title: dto.title,
            notes: dto.notes,
            plannedForDate: planned,
            originalPlannedDate: planned,
            dueDate: dto.dueDate,
            completedDate: completedDate,
            status: status,
            priority: dto.priority,
            source: .reminders,
            externalIdentifier: dto.externalIdentifier
        )
        todo.externalModifiedAt = dto.modifiedAt
        return todo
    }

    public static func dto(from todo: DailyTodo) -> ReminderDTO? {
        guard let externalIdentifier = todo.externalIdentifier else { return nil }
        return ReminderDTO(
            externalIdentifier: externalIdentifier,
            title: todo.title,
            notes: todo.notes,
            dueDate: todo.dueDate ?? todo.plannedForDate,
            isCompleted: todo.isCompleted,
            completionDate: todo.completedDate,
            priority: todo.priority,
            modifiedAt: todo.externalModifiedAt
        )
    }

    /// Maps EventKit priority (0 = none, 1–4 low, 5 med, 6–9 high) to DayBar priority.
    public static func priority(fromEventKit raw: Int) -> Priority {
        switch raw {
        case 6...9: return .high
        case 1...4: return .low
        default: return .medium
        }
    }

    public static func eventKitPriority(from priority: Priority) -> Int {
        switch priority {
        case .low: return 1
        case .medium: return 5
        case .high: return 9
        }
    }
}