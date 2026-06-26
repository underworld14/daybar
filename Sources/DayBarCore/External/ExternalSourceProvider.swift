import Foundation

/// Protocol boundary for external task sources (Apple Reminders today; Calendar later).
@MainActor
public protocol ExternalSourceProvider: AnyObject {
    var accessStatus: RemindersAccessStatus { get }
    func requestAccess() async throws -> Bool
    func fetchLists() async throws -> [ReminderListDTO]
    func fetchIncomplete(
        calendarIdentifiers: [String],
        through endOfDay: Date,
        includeUndated: Bool
    ) async throws -> [ReminderDTO]
    func createReminder(
        title: String,
        notes: String,
        dueDate: Date?,
        priority: Priority,
        calendarIdentifier: String
    ) async throws -> ReminderDTO
    /// Applies changes and returns the post-save reminder (for `lastModifiedDate`).
    func apply(_ dto: ReminderDTO) async throws -> ReminderDTO
    /// Returns the reminder regardless of completion status; `nil` when deleted remotely.
    func fetchReminder(externalIdentifier: String) async throws -> ReminderDTO?

    // MARK: - Recurring habit reminders

    func fetchHabitReminders(calendarIdentifiers: [String]) async throws -> [HabitReminderDTO]
    func createHabitReminder(
        _ dto: HabitReminderDTO,
        calendarIdentifier: String
    ) async throws -> HabitReminderDTO
    func applyHabitReminder(_ dto: HabitReminderDTO) async throws -> HabitReminderDTO
    func fetchHabitReminder(externalIdentifier: String) async throws -> HabitReminderDTO?
}