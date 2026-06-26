import Foundation
import EventKit

/// EventKit-backed provider for Apple Reminders.
@MainActor
public final class RemindersAdapter: ExternalSourceProvider {
    private let eventStore: EKEventStore
    private let calendar: Calendar

    public init(eventStore: EKEventStore = EKEventStore(), calendar: Calendar = .current) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    public var accessStatus: RemindersAccessStatus {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: return .notDetermined
        case .fullAccess, .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .writeOnly: return .denied
        @unknown default: return .denied
        }
    }

    public func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToReminders()
    }

    public func fetchLists() async throws -> [ReminderListDTO] {
        eventStore.calendars(for: .reminder).map {
            ReminderListDTO(calendarIdentifier: $0.calendarIdentifier, title: $0.title)
        }
    }

    public func fetchIncomplete(
        calendarIdentifiers: [String],
        through endOfDay: Date,
        includeUndated: Bool
    ) async throws -> [ReminderDTO] {
        guard !calendarIdentifiers.isEmpty else { return [] }
        let calendars = eventStore.calendars(for: .reminder)
            .filter { calendarIdentifiers.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endOfDay)) ?? endOfDay
        var results: [ReminderDTO] = []

        let datedPredicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: end,
            calendars: calendars
        )
        let dated = try await fetchReminders(matching: datedPredicate)
        results.append(contentsOf: dated.map { mapReminder($0) })

        if includeUndated {
            let allPredicate = eventStore.predicateForReminders(in: calendars)
            let all = try await fetchReminders(matching: allPredicate)
            let datedIDs = Set(results.map(\.externalIdentifier))
            for reminder in all where !reminder.isCompleted && reminder.dueDateComponents == nil {
                let dto = mapReminder(reminder)
                if !datedIDs.contains(dto.externalIdentifier) {
                    results.append(dto)
                }
            }
        }

        return results
    }

    public func createReminder(
        title: String,
        notes: String,
        dueDate: Date?,
        priority: Priority,
        calendarIdentifier: String
    ) async throws -> ReminderDTO {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes.isEmpty ? nil : notes
        reminder.priority = ReminderMapping.eventKitPriority(from: priority)
        if let cal = eventStore.calendar(withIdentifier: calendarIdentifier)
            ?? eventStore.defaultCalendarForNewReminders() {
            reminder.calendar = cal
        }
        if let dueDate {
            reminder.dueDateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        try eventStore.save(reminder, commit: true)
        return mapReminder(reminder)
    }

    public func apply(_ dto: ReminderDTO) async throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: dto.externalIdentifier) as? EKReminder else {
            return
        }
        reminder.title = dto.title
        reminder.notes = dto.notes.isEmpty ? nil : dto.notes
        reminder.priority = ReminderMapping.eventKitPriority(from: dto.priority)
        if let due = dto.dueDate {
            reminder.dueDateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: due
            )
        } else {
            reminder.dueDateComponents = nil
        }
        reminder.isCompleted = dto.isCompleted
        reminder.completionDate = dto.isCompleted ? (dto.completionDate ?? Date()) : nil
        try eventStore.save(reminder, commit: true)
    }

    // MARK: - Private

    private func fetchReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func mapReminder(_ reminder: EKReminder) -> ReminderDTO {
        let due: Date?
        if let comps = reminder.dueDateComponents {
            due = calendar.date(from: comps)
        } else {
            due = nil
        }
        return ReminderDTO(
            externalIdentifier: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes ?? "",
            dueDate: due,
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            priority: ReminderMapping.priority(fromEventKit: reminder.priority),
            calendarIdentifier: reminder.calendar.calendarIdentifier,
            calendarTitle: reminder.calendar.title,
            modifiedAt: reminder.lastModifiedDate
        )
    }
}