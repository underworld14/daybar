import Foundation

/// Pulls Apple Reminders into SwiftData and pushes local mutations back to EventKit.
@MainActor
public final class RemindersSyncEngine {
    private let store: DataStore
    private let provider: ExternalSourceProvider
    private let calendar: Calendar
    private var pushQueue: Set<UUID> = []
    private var lastPullAt: Date?
    private let minPullInterval: TimeInterval = 60

    public private(set) var lastSyncError: String?
    public private(set) var lastSyncedAt: Date?

    public init(
        store: DataStore,
        provider: ExternalSourceProvider,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.provider = provider
        self.calendar = calendar
    }

    public var accessStatus: RemindersAccessStatus { provider.accessStatus }

    public func requestAccess() async -> Bool {
        do {
            return try await provider.requestAccess()
        } catch {
            lastSyncError = error.localizedDescription
            return false
        }
    }

    public func fetchLists() async -> [ReminderListDTO] {
        guard provider.accessStatus == .authorized else { return [] }
        do {
            return try await provider.fetchLists()
        } catch {
            lastSyncError = error.localizedDescription
            return []
        }
    }

    public func enqueuePush(for todo: DailyTodo) {
        guard todo.source == .reminders, todo.externalIdentifier != nil else { return }
        pushQueue.insert(todo.id)
    }

    @discardableResult
    public func reconcileIfNeeded(now: Date = .now, force: Bool = false) async -> Bool {
        guard Preferences.remindersSyncEnabled else { return false }
        guard provider.accessStatus == .authorized else { return false }
        let selected = Preferences.selectedReminderCalendarIDs
        guard !selected.isEmpty else { return false }

        if !force, let lastPullAt, now.timeIntervalSince(lastPullAt) < minPullInterval, pushQueue.isEmpty {
            return false
        }

        await processPushQueue(now: now)
        await pull(now: now, calendarIDs: selected)
        lastPullAt = now
        if let meta = try? store.appMeta() {
            meta.remindersLastSyncedAt = now
            store.save()
        }
        return true
    }

    public func createReminderForNewTodo(_ todo: DailyTodo, now: Date) async {
        guard Preferences.remindersPushNewTodos else { return }
        let listID = Preferences.defaultReminderCalendarID ?? Preferences.selectedReminderCalendarIDs.first
        guard let listID, provider.accessStatus == .authorized else { return }
        do {
            let dto = try await provider.createReminder(
                title: todo.title,
                notes: todo.notes,
                dueDate: todo.plannedForDate,
                priority: todo.priority,
                calendarIdentifier: listID
            )
            todo.source = .reminders
            todo.externalIdentifier = dto.externalIdentifier
            todo.externalModifiedAt = dto.modifiedAt
            store.save()
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    // MARK: - Private

    private func processPushQueue(now: Date) async {
        guard !pushQueue.isEmpty else { return }
        let ids = pushQueue
        pushQueue.removeAll()
        let all = (try? store.allTodos()) ?? []
        for todo in all where ids.contains(todo.id) {
            guard var dto = ReminderMapping.dto(from: todo) else { continue }
            if todo.status == .dropped {
                dto.isCompleted = true
                dto.completionDate = now
            }
            do {
                try await provider.apply(dto)
                lastSyncError = nil
            } catch {
                lastSyncError = error.localizedDescription
                pushQueue.insert(todo.id)
            }
        }
    }

    private func pull(now: Date, calendarIDs: [String]) async {
        let today = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: today)?.addingTimeInterval(-1) ?? now
        do {
            let incoming = try await provider.fetchIncomplete(
                calendarIdentifiers: calendarIDs,
                through: endOfDay,
                includeUndated: Preferences.remindersIncludeUndated
            )
            var seen = Set<String>()
            for dto in incoming where !dto.title.isEmpty {
                seen.insert(dto.externalIdentifier)
                if let existing = try? store.todo(externalIdentifier: dto.externalIdentifier) {
                    if shouldApplyRemote(dto, over: existing) {
                        ReminderMapping.apply(dto, to: existing, today: now, calendar: calendar)
                    }
                } else {
                    store.insert(ReminderMapping.makeTodo(from: dto, today: now, calendar: calendar))
                }
            }
            pruneRemindersMirrors(keeping: seen)
            lastSyncedAt = now
            lastSyncError = nil
            store.save()
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private func shouldApplyRemote(_ dto: ReminderDTO, over todo: DailyTodo) -> Bool {
        guard let remote = dto.modifiedAt, let local = todo.externalModifiedAt else { return true }
        return remote >= local
    }

    private func pruneRemindersMirrors(keeping ids: Set<String>) {
        let mirrors = (try? store.remindersTodos()) ?? []
        for todo in mirrors {
            guard let ext = todo.externalIdentifier else { continue }
            if !ids.contains(ext) {
                store.delete(todo)
            }
        }
    }
}