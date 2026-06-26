import Foundation

/// Value-type bridge for recurring habit reminders in Apple Reminders.
public struct HabitReminderDTO: Sendable, Equatable {
    public var externalIdentifier: String
    public var templateId: UUID
    public var title: String
    public var notes: String
    public var dueDate: Date?
    public var isCompleted: Bool
    public var completionDate: Date?
    public var calendarIdentifier: String
    public var calendarTitle: String
    public var modifiedAt: Date?
    public var schedulePreset: HabitSchedulePreset
    public var weekdayMask: Int

    public init(
        externalIdentifier: String,
        templateId: UUID,
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completionDate: Date? = nil,
        calendarIdentifier: String = "",
        calendarTitle: String = "",
        modifiedAt: Date? = nil,
        schedulePreset: HabitSchedulePreset = .everyDay,
        weekdayMask: Int = HabitSchedule.allDaysMask
    ) {
        self.externalIdentifier = externalIdentifier
        self.templateId = templateId
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.modifiedAt = modifiedAt
        self.schedulePreset = schedulePreset
        self.weekdayMask = weekdayMask
    }
}