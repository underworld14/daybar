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

    func apply(_ dto: ReminderDTO) async throws {
        applied.append(dto)
        if let idx = reminders.firstIndex(where: { $0.externalIdentifier == dto.externalIdentifier }) {
            reminders[idx] = dto
        }
    }
}