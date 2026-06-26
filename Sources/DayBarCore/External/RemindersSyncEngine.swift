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
        if let persisted = try? store.appMeta().remindersLastSyncedAt {
            lastSyncedAt = persisted
        }
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

    /// Returns whether local todo data changed (push applied or pull updated mirrors).
    @discardableResult
    public func reconcileIfNeeded(now: Date = .now, force: Bool = false) async -> Bool {
        guard Preferences.remindersSyncEnabled else { return false }
        guard provider.accessStatus == .authorized else { return false }
        let selected = Preferences.selectedReminderCalendarIDs
        guard !selected.isEmpty else { return false }

        if !force, let lastPullAt, now.timeIntervalSince(lastPullAt) < minPullInterval, pushQueue.isEmpty {
            return false
        }

        let push = await processPushQueue(now: now)
        let pull = await pull(now: now, calendarIDs: selected)

        if push.allSucceeded, pull.succeeded, pull.reconcileAllSucceeded {
            lastSyncError = nil
            lastSyncedAt = now
            lastPullAt = now
            if let meta = try? store.appMeta() {
                meta.remindersLastSyncedAt = now
                store.save()
            }
        } else if pull.succeeded, pull.reconcileAllSucceeded, push.allSucceeded == false {
            // Pull ok but push still pending/failed — keep lastSyncError from push.
        } else if pull.succeeded, pull.reconcileAllSucceeded {
            lastSyncedAt = now
        }

        return push.changed || pull.changed
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

    private struct PushResult {
        var changed: Bool
        var allSucceeded: Bool
    }

    private struct PullResult {
        var succeeded: Bool
        var changed: Bool
        var reconcileAllSucceeded: Bool
    }

    private func processPushQueue(now: Date) async -> PushResult {
        guard !pushQueue.isEmpty else { return PushResult(changed: false, allSucceeded: true) }
        let ids = pushQueue
        pushQueue.removeAll()
        let all = (try? store.allTodos()) ?? []
        var changed = false
        var allSucceeded = true
        for todo in all where ids.contains(todo.id) {
            guard var dto = ReminderMapping.dto(from: todo) else { continue }
            if todo.status == .dropped {
                dto.isCompleted = true
                dto.completionDate = now
            }
            do {
                let updated = try await provider.apply(dto)
                todo.externalModifiedAt = updated.modifiedAt ?? now
                changed = true
            } catch {
                lastSyncError = error.localizedDescription
                pushQueue.insert(todo.id)
                allSucceeded = false
            }
        }
        store.save()
        return PushResult(changed: changed, allSucceeded: allSucceeded && pushQueue.isEmpty)
    }

    @discardableResult
    private func pull(now: Date, calendarIDs: [String]) async -> PullResult {
        let today = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: today)?.addingTimeInterval(-1) ?? now
        do {
            let incoming = try await provider.fetchIncomplete(
                calendarIdentifiers: calendarIDs,
                through: endOfDay,
                includeUndated: Preferences.remindersIncludeUndated
            )
            var seen = Set<String>()
            var changed = false
            for dto in incoming where !dto.title.isEmpty {
                seen.insert(dto.externalIdentifier)
                if let existing = try? store.todo(externalIdentifier: dto.externalIdentifier) {
                    if shouldApplyRemote(dto, over: existing) {
                        ReminderMapping.apply(dto, to: existing, today: now, calendar: calendar)
                        changed = true
                    }
                } else {
                    store.insert(ReminderMapping.makeTodo(from: dto, today: now, calendar: calendar))
                    changed = true
                }
            }
            let reconcileAllSucceeded = await reconcileMirrorsOffPullSet(keeping: seen, now: now, changed: &changed)
            store.save()
            return PullResult(succeeded: true, changed: changed, reconcileAllSucceeded: reconcileAllSucceeded)
        } catch {
            lastSyncError = error.localizedDescription
            return PullResult(succeeded: false, changed: false, reconcileAllSucceeded: false)
        }
    }

    private func shouldApplyRemote(_ dto: ReminderDTO, over todo: DailyTodo) -> Bool {
        guard let remote = dto.modifiedAt, let local = todo.externalModifiedAt else { return true }
        return remote >= local
    }

    /// Mirrors missing from the incomplete pull set may be completed, future-dated, or deleted remotely.
    private func reconcileMirrorsOffPullSet(
        keeping seen: Set<String>,
        now: Date,
        changed: inout Bool
    ) async -> Bool {
        let mirrors = (try? store.remindersTodos()) ?? []
        var allSucceeded = true
        for todo in mirrors {
            guard let ext = todo.externalIdentifier, !seen.contains(ext) else { continue }
            do {
                guard let remote = try await provider.fetchReminder(externalIdentifier: ext) else {
                    store.delete(todo)
                    changed = true
                    continue
                }
                if shouldApplyRemote(remote, over: todo) {
                    ReminderMapping.apply(remote, to: todo, today: now, calendar: calendar)
                    changed = true
                }
            } catch {
                lastSyncError = error.localizedDescription
                allSucceeded = false
            }
        }
        return allSucceeded
    }
}