import Foundation
import Observation
import EventKit
#if canImport(AppKit)
import AppKit
#endif

/// The single `@Observable` source of truth the whole UI observes. Owns the data store,
/// the rollover engine, and the Pomodoro engine, and exposes the user intents. One
/// observation system throughout (no `ObservableObject`), so nested engine changes
/// propagate to SwiftUI correctly.
@MainActor
@Observable
public final class AppState {
    public let store: DataStore
    public let pomodoro: PomodoroEngine
    public let notifications = NotificationScheduler()
    public let remindersSync: RemindersSyncEngine

    @ObservationIgnored private let rollover: RolloverEngine
    @ObservationIgnored private let habitEngine: HabitEngine
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var lastHabitNotifySignature: String?
    @ObservationIgnored private var forceRemindersSync = false
    @ObservationIgnored private var pendingRemindersSync = false
    @ObservationIgnored private var remindersSyncTask: Task<Void, Never>?

    public private(set) var remindersLastSyncedAt: Date?
    public private(set) var remindersLastSyncError: String?
    public private(set) var isRemindersSyncing = false

    public private(set) var todayTodos: [DailyTodo] = []
    public private(set) var carriedTodos: [DailyTodo] = []
    public private(set) var todayHabits: [TodayHabit] = []
    public private(set) var habitStreakEntries: [HabitStreakEntry] = []
    /// Ephemeral banner after hitting a streak milestone (7/30/100 days).
    public var habitMilestoneMessage: String?
    public var isPanelPresented: Bool = false
    public var presentEndOfDayReview: Bool = false
    /// Bumped to ask the panel to focus the quick-add field (e.g. from the global hotkey).
    public var quickAddFocusSignal: Int = 0

    public var thresholds: EscalationThresholds = .gentle

    public init(
        store: DataStore,
        calendar: Calendar = .current,
        remindersProvider: ExternalSourceProvider? = nil
    ) {
        self.store = store
        self.calendar = calendar
        self.rollover = RolloverEngine(store: store, calendar: calendar)
        self.habitEngine = HabitEngine(store: store, calendar: calendar)
        let provider = remindersProvider ?? RemindersAdapter(calendar: calendar)
        self.remindersSync = RemindersSyncEngine(store: store, provider: provider, calendar: calendar)
        self.remindersLastSyncedAt = remindersSync.lastSyncedAt
        self.pomodoro = PomodoroEngine()
        self.pomodoro.onPhaseEnd = { [weak self] phase, elapsed, natural in
            self?.handlePhaseEnd(phase, elapsed: elapsed, completedNaturally: natural)
        }
        applyPreferences()
        refresh()
        observeSystem()
    }

    // MARK: - Derived

    public var overdueCount: Int {
        carriedTodos.filter {
            EscalationModel.countsTowardBadge($0.escalationTier(thresholds: thresholds, calendar: calendar))
        }.count
    }

    public var worstTier: EscalationTier {
        carriedTodos.map { $0.escalationTier(thresholds: thresholds, calendar: calendar) }.max() ?? .onPlan
    }

    public var completedTodayCount: Int { todayTodos.filter(\.isCompleted).count }
    public var totalTodayCount: Int { todayTodos.count }
    public var completedHabitsTodayCount: Int { todayHabits.filter { $0.log.isCompleted }.count }
    public var totalHabitsTodayCount: Int { todayHabits.count }

    // MARK: - Refresh

    /// Reconciles the day (idempotent rollover) and reloads the today/carried lists.
    public func refresh(now: Date = .now) {
        rollover.performRolloverIfNeeded(now: now)
        habitEngine.materializeIfNeeded(now: now)
        reloadLists(now: now)
        let rawHabits = (try? store.todayHabits(on: now, calendar: calendar)) ?? []
        rebuildHabitCaches(rawHabits: rawHabits, now: now)
        notifications.updateBacklogNudge(agingCount: overdueCount, now: now, calendar: calendar)
        rescheduleHabitNotificationsIfNeeded(now: now)
        maybePromptEndOfDayReview(now: now)
        scheduleRemindersSync(now: now)
    }

    public func invalidateRemindersSync() {
        forceRemindersSync = true
    }

    private func markRemindersTodoLocallyModified(_ todo: DailyTodo, now: Date) {
        guard todo.source == .reminders else { return }
        todo.externalModifiedAt = now
        invalidateRemindersSync()
    }

    private func reloadLists(now: Date) {
        todayTodos = (try? store.todos(on: now, calendar: calendar)) ?? []
        carriedTodos = (try? store.overdueIncompleteTodos(before: now, calendar: calendar)) ?? []
    }

    private func scheduleRemindersSync(now: Date) {
        guard Preferences.remindersSyncEnabled else { return }
        if remindersSyncTask != nil {
            pendingRemindersSync = true
            return
        }
        runRemindersSync(now: now)
    }

    private func runRemindersSync(now: Date) {
        let force = forceRemindersSync
        forceRemindersSync = false
        isRemindersSyncing = true
        remindersSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isRemindersSyncing = false
                self.remindersSyncTask = nil
                self.remindersLastSyncedAt = self.remindersSync.lastSyncedAt
                self.remindersLastSyncError = self.remindersSync.lastSyncError
                if self.pendingRemindersSync {
                    self.pendingRemindersSync = false
                    self.runRemindersSync(now: .now)
                }
            }
            let changed = await self.remindersSync.reconcileIfNeeded(now: now, force: force)
            self.remindersLastSyncedAt = self.remindersSync.lastSyncedAt
            self.remindersLastSyncError = self.remindersSync.lastSyncError
            if changed {
                self.reloadLists(now: now)
                let rawHabits = (try? self.store.todayHabits(on: now, calendar: self.calendar)) ?? []
                self.rebuildHabitCaches(rawHabits: rawHabits, now: now)
            }
        }
    }

    // MARK: - Intents

    @discardableResult
    public func addTodo(title: String, priority: Priority = .medium, now: Date = .now) -> DailyTodo? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let day = DayMath.startOfDay(now, calendar: calendar)
        let todo = DailyTodo(title: trimmed, plannedForDate: day, originalPlannedDate: day, status: .planned, priority: priority)
        store.insert(todo)
        store.save()
        if Preferences.remindersPushNewTodos {
            Task { await remindersSync.createReminderForNewTodo(todo, now: now) }
        }
        refresh(now: now)
        return todo
    }

    public func toggleComplete(_ todo: DailyTodo, now: Date = .now) {
        if todo.isCompleted {
            todo.completedDate = nil
            let today = DayMath.startOfDay(now, calendar: calendar)
            todo.status = todo.plannedForDate < today ? .carriedOver : .planned
        } else {
            todo.completedDate = now
            todo.status = .completed
        }
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        store.save()
        refresh(now: now)
    }

    /// Push a task to tomorrow.
    public func delay(_ todo: DailyTodo, now: Date = .now) {
        todo.delayCount += 1
        let tomorrow = DayMath.nextDay(now, calendar: calendar)
        todo.plannedForDate = tomorrow
        todo.snoozedUntil = tomorrow
        todo.status = .snoozed
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        store.save()
        refresh(now: now)
    }

    /// Bring a carried-over task into today (its age is preserved via originalPlannedDate).
    public func reschedule(_ todo: DailyTodo, to day: Date = .now, now: Date = .now) {
        todo.plannedForDate = DayMath.startOfDay(day, calendar: calendar)
        todo.snoozedUntil = nil
        todo.status = .planned
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        store.save()
        refresh(now: now)
    }

    public func drop(_ todo: DailyTodo, now: Date = .now) {
        todo.status = .dropped
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        store.save()
        refresh(now: now)
    }

    /// Rename a task. No-op for an empty/whitespace or unchanged title.
    public func rename(_ todo: DailyTodo, to title: String, now: Date = .now) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != todo.title else { return }
        todo.title = trimmed
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        store.save()
        refresh(now: now)
    }

    // MARK: - Habits

    @discardableResult
    public func addHabitTemplate(
        title: String,
        cueText: String = "",
        symbolName: String = "circle",
        anchorHour: Int? = nil,
        anchorMinute: Int? = nil,
        notifyEnabled: Bool = false,
        now: Date = .now
    ) -> HabitTemplate? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let order = (try? store.activeHabitTemplates().count) ?? 0
        let template = HabitTemplate(
            title: trimmed,
            cueText: cueText.trimmingCharacters(in: .whitespacesAndNewlines),
            symbolName: symbolName,
            sortOrder: order,
            anchorHour: anchorHour,
            anchorMinute: anchorMinute,
            notifyEnabled: notifyEnabled
        )
        store.insert(template)
        store.save()
        invalidateHabitNotifications()
        refresh(now: now)
        return template
    }

    public func updateHabitTemplate(_ template: HabitTemplate, now: Date = .now) {
        store.save()
        invalidateHabitNotifications()
        refresh(now: now)
    }

    public func archiveHabitTemplate(_ template: HabitTemplate, now: Date = .now) {
        template.isActive = false
        store.save()
        invalidateHabitNotifications()
        refresh(now: now)
    }

    public func toggleHabit(_ log: HabitLog, now: Date = .now) {
        let priorStreak = habitStreakEntries.first(where: { $0.template.id == log.templateId })?.streak.current ?? 0
        if log.isCompleted {
            log.completedAt = nil
            log.status = .pending
            habitMilestoneMessage = nil
        } else if log.status == .skipped {
            log.completedAt = now
            log.status = .completed
        } else {
            log.completedAt = now
            log.status = .completed
            let newStreak = priorStreak + 1
            if HabitAnalytics.isMilestone(newStreak), newStreak > priorStreak,
               let title = todayHabits.first(where: { $0.log.id == log.id })?.template.title {
                habitMilestoneMessage = "\(newStreak) days of “\(title)” — keep going."
            }
        }
        store.save()
        reloadLists(now: now)
        let rawHabits = (try? store.todayHabits(on: now, calendar: calendar)) ?? []
        rebuildHabitCaches(rawHabits: rawHabits, now: now)
    }

    public func skipHabit(_ log: HabitLog, now: Date = .now) {
        log.completedAt = nil
        log.status = .skipped
        store.save()
        refresh(now: now)
    }

    public func streak(for templateId: UUID) -> Int {
        habitStreakEntries.first(where: { $0.template.id == templateId })?.streak.current ?? 0
    }

    public func habitStatBuckets(granularity: Granularity, count: Int, now: Date = .now) -> [HabitStatBucket] {
        let range = Analytics.range(endingAt: now, count: count, granularity: granularity, calendar: calendar)
        let logs = (try? store.habitLogs(in: range)) ?? []
        return HabitAnalytics.buckets(logs: logs, endingAt: now, count: count, granularity: granularity, calendar: calendar)
    }

    public func habitHeatmap(templateId: UUID) -> [HabitHeatmapCell] {
        habitStreakEntries.first(where: { $0.template.id == templateId })?.heatmap ?? []
    }

    public func habitStreaks() -> [HabitStreakEntry] {
        habitStreakEntries
    }

    /// Clears the notification debounce so the next `refresh()` reschedules habit anchors.
    public func invalidateHabitNotifications() {
        lastHabitNotifySignature = nil
    }

    private func rebuildHabitCaches(rawHabits: [TodayHabit], now: Date) {
        let today = calendar.startOfDay(for: now)
        let lookbackStart = calendar.date(
            byAdding: .day, value: -HabitAnalytics.cacheLookbackDays, to: today
        ) ?? today
        let logs = (try? store.habitLogs(since: lookbackStart, through: today, calendar: calendar)) ?? []
        let templates = analyticsTemplates(withHistoryIn: logs)
        habitStreakEntries = templates.map { template in
            let streak = HabitAnalytics.streakInfo(
                logs: logs, templateId: template.id, asOf: now, calendar: calendar
            )
            let heatmap = HabitAnalytics.heatmap(
                logs: logs, templateId: template.id, days: 28, endingAt: now, calendar: calendar
            )
            return HabitStreakEntry(template: template, streak: streak, heatmap: heatmap)
        }
        let streakByTemplate = Dictionary(uniqueKeysWithValues: habitStreakEntries.map { ($0.template.id, $0.streak) })
        todayHabits = rawHabits.map { habit in
            let info = streakByTemplate[habit.template.id]
            return TodayHabit(
                template: habit.template,
                log: habit.log,
                currentStreak: info?.current ?? 0,
                graceRemaining: info?.graceRemaining ?? HabitAnalytics.gracePerWeek
            )
        }
    }

    private func analyticsTemplates(withHistoryIn logs: [HabitLog]) -> [HabitTemplate] {
        let all = (try? store.allHabitTemplates()) ?? []
        let loggedTemplateIds = Set(logs.map(\.templateId))
        return all
            .filter { $0.isActive || loggedTemplateIds.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func rescheduleHabitNotificationsIfNeeded(now: Date = .now) {
        let templates = (try? store.activeHabitTemplates()) ?? []
        let logs = (try? store.habitLogs(on: now, calendar: calendar)) ?? []
        let signature = HabitNotifySignature.make(
            templates: templates,
            todayLogs: logs,
            habitNotifyEnabled: Preferences.habitNotifyEnabled
        )
        guard signature != lastHabitNotifySignature else { return }
        lastHabitNotifySignature = signature
        notifications.rescheduleHabitAnchors(templates: templates, todayLogs: logs)
    }

    /// One-button Pomodoro control: start when idle, pause when running, resume when paused.
    public func togglePomodoro() {
        if pomodoro.phase == .idle {
            pomodoro.startWork()
        } else if pomodoro.isRunning {
            pomodoro.pause()
        } else {
            pomodoro.resume()
        }
    }

    /// Rebuild the Pomodoro configuration from saved Preferences (call after a Settings change).
    public func applyPreferences() {
        pomodoro.config = Preferences.pomodoroConfig
    }

    // MARK: - Analytics

    public func statBuckets(granularity: Granularity, count: Int, now: Date = .now) -> [StatBucket] {
        let range = Analytics.range(endingAt: now, count: count, granularity: granularity, calendar: calendar)
        let todos = (try? store.todos(plannedIn: range)) ?? []
        let sessions = (try? store.focusSessions(in: range)) ?? []
        return Analytics.buckets(todos: todos, sessions: sessions, endingAt: now, count: count, granularity: granularity, calendar: calendar)
    }

    // MARK: - End-of-day review

    public func hasReviewedToday(now: Date = .now) -> Bool {
        store.hasDayLog(on: now, calendar: calendar)
    }

    public func saveDayLog(reflection: String, now: Date = .now) {
        store.upsertDayLog(
            day: now,
            reflection: reflection,
            plannedCount: totalTodayCount,
            completedCount: completedTodayCount,
            calendar: calendar
        )
        presentEndOfDayReview = false
    }

    private func maybePromptEndOfDayReview(now: Date = .now) {
        guard !presentEndOfDayReview, !hasReviewedToday(now: now), totalTodayCount > 0 else { return }
        if now >= Preferences.eveningTime(on: now, calendar: calendar) {
            presentEndOfDayReview = true
        }
    }

    // MARK: - System wiring

    private func observeSystem() {
        #if canImport(AppKit)
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        }
        observers.append(wake)
        #endif

        let dayChange = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append(dayChange)

        let remindersChange = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateRemindersSync()
                self?.refresh()
            }
        }
        observers.append(remindersChange)
    }

    private func handleWake() {
        pomodoro.tick()
        refresh()
    }

    private func handlePhaseEnd(_ phase: PomodoroPhase, elapsed: TimeInterval, completedNaturally: Bool) {
        if phase == .work {
            let minutes = Int((elapsed / 60).rounded())
            if minutes > 0 {
                store.insert(FocusSession(endedAt: .now, minutes: minutes, completed: completedNaturally))
                store.save()
            }
        }
        #if canImport(AppKit)
        if Preferences.soundEnabled { AppKitBridge.playPhaseEndSound(named: Preferences.soundName) }
        #endif
        notifications.postPhaseEndBanner(finished: phase)
    }
}
