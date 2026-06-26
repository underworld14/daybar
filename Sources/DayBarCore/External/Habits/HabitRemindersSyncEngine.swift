import Foundation

/// Pulls recurring habit reminders from Apple Reminders and pushes local habit mutations back.
@MainActor
public final class HabitRemindersSyncEngine {
    private let store: DataStore
    private let provider: ExternalSourceProvider
    private let calendar: Calendar
    private var pushQueue: Set<UUID> = []
    private var lastPullAt: Date?
    private let minPullInterval: TimeInterval = 60

    public private(set) var lastSyncError: String?

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

    public func enqueuePush(for template: HabitTemplate) {
        guard template.remindersSyncEnabled else { return }
        pushQueue.insert(template.id)
    }

    @discardableResult
    public func reconcileIfNeeded(now: Date = .now, force: Bool = false) async -> Bool {
        guard Preferences.remindersHabitsSyncEnabled else { return false }
        guard provider.accessStatus == .authorized else { return false }
        let calendarIDs = Preferences.effectiveHabitReminderCalendarIDs
        guard !calendarIDs.isEmpty else { return false }

        if !force, let lastPullAt, now.timeIntervalSince(lastPullAt) < minPullInterval, pushQueue.isEmpty {
            return false
        }

        let push = await processPushQueue(now: now, calendarIDs: calendarIDs)
        let pull = await pull(now: now, calendarIDs: calendarIDs)

        if push.allSucceeded, pull.succeeded, pull.reconcileAllSucceeded {
            lastSyncError = nil
            lastPullAt = now
        }

        return push.changed || pull.changed
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

    private func processPushQueue(now: Date, calendarIDs: [String]) async -> PushResult {
        var changed = false
        var allSucceeded = true
        let ids = pushQueue
        pushQueue.removeAll()

        let templates = (try? store.allHabitTemplates()) ?? []
        for template in templates where ids.contains(template.id) {
            guard template.remindersSyncEnabled, template.isActive else { continue }
            do {
                if let externalId = template.externalReminderIdentifier {
                    var dto = HabitReminderMapping.dto(from: template, calendar: calendar, referenceDay: now)
                    dto.externalIdentifier = externalId
                    if let log = try? store.habitLogs(on: now, calendar: calendar)
                        .first(where: { $0.templateId == template.id }) {
                        dto.isCompleted = log.isCompleted
                        dto.completionDate = log.completedAt
                    }
                    let updated = try await provider.applyHabitReminder(dto)
                    template.externalModifiedAt = updated.modifiedAt ?? now
                    changed = true
                } else {
                    let listID = template.remindersCalendarIdentifier
                        ?? Preferences.defaultHabitReminderCalendarID
                        ?? calendarIDs.first
                    guard let listID else { continue }
                    var dto = HabitReminderMapping.dto(from: template, calendar: calendar, referenceDay: now)
                    let created = try await provider.createHabitReminder(dto, calendarIdentifier: listID)
                    template.externalReminderIdentifier = created.externalIdentifier
                    template.externalModifiedAt = created.modifiedAt ?? now
                    template.remindersCalendarIdentifier = created.calendarIdentifier
                    changed = true
                }
            } catch {
                lastSyncError = error.localizedDescription
                pushQueue.insert(template.id)
                allSucceeded = false
            }
        }

        for template in templates where ids.contains(template.id) && !template.isActive {
            guard let externalId = template.externalReminderIdentifier else { continue }
            do {
                if var remote = try await provider.fetchHabitReminder(externalIdentifier: externalId) {
                    remote.isCompleted = true
                    remote.completionDate = now
                    let updated = try await provider.applyHabitReminder(remote)
                    template.externalModifiedAt = updated.modifiedAt ?? now
                }
                template.externalReminderIdentifier = nil
                template.remindersSyncEnabled = false
                changed = true
            } catch {
                lastSyncError = error.localizedDescription
                allSucceeded = false
            }
        }

        store.save()
        return PushResult(changed: changed, allSucceeded: allSucceeded && pushQueue.isEmpty)
    }

    @discardableResult
    private func pull(now: Date, calendarIDs: [String]) async -> PullResult {
        let today = calendar.startOfDay(for: now)
        do {
            let incoming = try await provider.fetchHabitReminders(calendarIdentifiers: calendarIDs)
            var seen = Set<String>()
            var changed = false

            for dto in incoming where !dto.title.isEmpty {
                seen.insert(dto.externalIdentifier)
                let template: HabitTemplate?
                if let byExt = try? store.habitTemplate(externalReminderIdentifier: dto.externalIdentifier) {
                    template = byExt
                } else if let byId = try? store.habitTemplate(id: dto.templateId) {
                    template = byId
                } else {
                    template = nil
                }

                if let template {
                    if HabitReminderMapping.shouldApplyRemote(dto, over: template) {
                        HabitReminderMapping.applyMetadata(dto, to: template)
                        if template.externalReminderIdentifier == nil {
                            template.externalReminderIdentifier = dto.externalIdentifier
                            template.remindersSyncEnabled = true
                        }
                        changed = true
                    }
                    if let log = try? store.habitLogs(on: today, calendar: calendar)
                        .first(where: { $0.templateId == template.id }) {
                        let prior = log.isCompleted
                        HabitReminderMapping.applyCompletion(
                            remoteCompleted: dto.isCompleted,
                            completionDate: dto.completionDate,
                            to: log,
                            today: now
                        )
                        if log.isCompleted != prior { changed = true }
                    }
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

    private func reconcileMirrorsOffPullSet(
        keeping seen: Set<String>,
        now: Date,
        changed: inout Bool
    ) async -> Bool {
        let mirrors = (try? store.syncedHabitTemplates()) ?? []
        var allSucceeded = true
        let today = calendar.startOfDay(for: now)
        for template in mirrors {
            guard let ext = template.externalReminderIdentifier, !seen.contains(ext) else { continue }
            do {
                guard let remote = try await provider.fetchHabitReminder(externalIdentifier: ext) else {
                    template.externalReminderIdentifier = nil
                    changed = true
                    continue
                }
                if HabitReminderMapping.shouldApplyRemote(remote, over: template) {
                    HabitReminderMapping.applyMetadata(remote, to: template)
                    if let log = try? store.habitLogs(on: today, calendar: calendar)
                        .first(where: { $0.templateId == template.id }) {
                        HabitReminderMapping.applyCompletion(
                            remoteCompleted: remote.isCompleted,
                            completionDate: remote.completionDate,
                            to: log,
                            today: now
                        )
                    }
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