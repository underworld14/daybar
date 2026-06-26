import Foundation
@testable import DayBarCore

@MainActor
final class MockRemindersProvider: ExternalSourceProvider {
    var accessStatus: RemindersAccessStatus = .authorized
    var lists: [ReminderListDTO] = [ReminderListDTO(calendarIdentifier: "list-1", title: "Personal")]
    var reminders: [ReminderDTO] = []
    var applied: [ReminderDTO] = []
    var created: [ReminderDTO] = []
    var shouldThrow = false
    var failApplyIdentifiers: Set<String> = []
    var fetchReminderThrowIdentifiers: Set<String> = []
    var fetchIncompleteDelayNanoseconds: UInt64 = 0
    var fetchIncompleteCallCount = 0
    var habitReminders: [HabitReminderDTO] = []
    var appliedHabits: [HabitReminderDTO] = []
    var createdHabits: [HabitReminderDTO] = []

    func requestAccess() async throws -> Bool {
        accessStatus = .authorized
        return true
    }

    func fetchLists() async throws -> [ReminderListDTO] {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        return lists
    }

    func fetchIncomplete(
        calendarIdentifiers: [String],
        through endOfDay: Date,
        includeUndated: Bool
    ) async throws -> [ReminderDTO] {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        fetchIncompleteCallCount += 1
        if fetchIncompleteDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fetchIncompleteDelayNanoseconds)
        }
        return reminders.filter { calendarIdentifiers.contains($0.calendarIdentifier) && !$0.isCompleted }
    }

    func createReminder(
        title: String,
        notes: String,
        dueDate: Date?,
        priority: Priority,
        calendarIdentifier: String
    ) async throws -> ReminderDTO {
        let dto = ReminderDTO(
            externalIdentifier: "new-\(created.count + 1)",
            title: title,
            notes: notes,
            dueDate: dueDate,
            priority: priority,
            calendarIdentifier: calendarIdentifier,
            calendarTitle: "Personal"
        )
        created.append(dto)
        reminders.append(dto)
        return dto
    }

    func apply(_ dto: ReminderDTO) async throws -> ReminderDTO {
        if failApplyIdentifiers.contains(dto.externalIdentifier) {
            throw RemindersProviderError.reminderNotFound(dto.externalIdentifier)
        }
        guard let idx = reminders.firstIndex(where: { $0.externalIdentifier == dto.externalIdentifier }) else {
            throw RemindersProviderError.reminderNotFound(dto.externalIdentifier)
        }
        applied.append(dto)
        var updated = dto
        updated.modifiedAt = dto.completionDate ?? dto.modifiedAt ?? Date()
        reminders[idx] = updated
        return updated
    }

    func fetchReminder(externalIdentifier: String) async throws -> ReminderDTO? {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        if fetchReminderThrowIdentifiers.contains(externalIdentifier) {
            throw NSError(domain: "test", code: 2)
        }
        return reminders.first { $0.externalIdentifier == externalIdentifier }
    }

    func fetchHabitReminders(calendarIdentifiers: [String]) async throws -> [HabitReminderDTO] {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        return habitReminders.filter { calendarIdentifiers.contains($0.calendarIdentifier) }
    }

    func createHabitReminder(
        _ dto: HabitReminderDTO,
        calendarIdentifier: String
    ) async throws -> HabitReminderDTO {
        var created = dto
        created.externalIdentifier = "habit-\(createdHabits.count + 1)"
        created.calendarIdentifier = calendarIdentifier
        created.modifiedAt = Date()
        createdHabits.append(created)
        habitReminders.append(created)
        return created
    }

    func applyHabitReminder(_ dto: HabitReminderDTO) async throws -> HabitReminderDTO {
        guard let idx = habitReminders.firstIndex(where: { $0.externalIdentifier == dto.externalIdentifier }) else {
            throw RemindersProviderError.reminderNotFound(dto.externalIdentifier)
        }
        appliedHabits.append(dto)
        var updated = dto
        updated.modifiedAt = dto.completionDate ?? dto.modifiedAt ?? Date()
        habitReminders[idx] = updated
        return updated
    }

    func fetchHabitReminder(externalIdentifier: String) async throws -> HabitReminderDTO? {
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        return habitReminders.first { $0.externalIdentifier == externalIdentifier }
    }
}