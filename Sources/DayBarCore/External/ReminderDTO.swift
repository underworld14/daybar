import Foundation

/// Value-type bridge for Apple Reminders data. Keeps EventKit out of sync logic and tests.
public struct ReminderDTO: Sendable, Equatable {
    public var externalIdentifier: String
    public var title: String
    public var notes: String
    public var dueDate: Date?
    public var isCompleted: Bool
    public var completionDate: Date?
    public var priority: Priority
    public var calendarIdentifier: String
    public var calendarTitle: String
    public var modifiedAt: Date?

    public init(
        externalIdentifier: String,
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completionDate: Date? = nil,
        priority: Priority = .medium,
        calendarIdentifier: String = "",
        calendarTitle: String = "",
        modifiedAt: Date? = nil
    ) {
        self.externalIdentifier = externalIdentifier
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.priority = priority
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.modifiedAt = modifiedAt
    }
}

public struct ReminderListDTO: Sendable, Equatable, Identifiable {
    public var id: String { calendarIdentifier }
    public let calendarIdentifier: String
    public let title: String

    public init(calendarIdentifier: String, title: String) {
        self.calendarIdentifier = calendarIdentifier
        self.title = title
    }
}

public enum RemindersAccessStatus: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}