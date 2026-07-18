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
    public let habitRemindersSync: HabitRemindersSyncEngine
    public let radio: RadioPlayerManager
    public let moodChecker: MoodAIAvailabilityChecking

    @ObservationIgnored private let rollover: RolloverEngine
    @ObservationIgnored private let habitEngine: HabitEngine
    @ObservationIgnored private let somaFM = SomaFMService()
    @ObservationIgnored private let artworkCache = RadioArtworkCache()
    @ObservationIgnored private var calendar: Calendar
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var pendingUndo: PendingUndo?
    @ObservationIgnored private var lastHabitNotifySignature: String?
    @ObservationIgnored private var forceRemindersSync = false
    @ObservationIgnored private var pendingRemindersSync = false
    @ObservationIgnored private var remindersSyncTask: Task<Void, Never>?
    @ObservationIgnored private let schedulesRemindersSync: Bool
    @ObservationIgnored private let observeSystemEvents: Bool
    @ObservationIgnored private var breakArmedAt: Date?
    @ObservationIgnored private var idlePollTimer: Timer?
    @ObservationIgnored private var suppressNextPhaseEndFeedback = false
    @ObservationIgnored private var reviewSnoozedUntil: Date?

    public private(set) var remindersLastSyncedAt: Date?
    public private(set) var remindersLastSyncError: String?
    public private(set) var isRemindersSyncing = false
    /// Published EventKit auth so Settings re-renders after grant without an off→on toggle.
    public private(set) var remindersAccessStatus: RemindersAccessStatus = .notDetermined

    public private(set) var todayTodos: [DailyTodo] = []
    public private(set) var tomorrowTodos: [DailyTodo] = []
    public private(set) var carriedTodos: [DailyTodo] = []
    public private(set) var todayHabits: [TodayHabit] = []
    public private(set) var habitStreakEntries: [HabitStreakEntry] = []
    /// Focus streak + 7-day Dayscape strip (computed from completed Pomodoros).
    public private(set) var focusStreakEntry: FocusStreakEntry?
    /// Focus garden snapshot for the Today panel / Analytics.
    public private(set) var gardenSnapshot: GardenSnapshot?
    /// Which panel-level tab the menu popover shows. Observed by the AppKit height tracker.
    public var selectedPanelTab: PanelTab = .today
    /// Ephemeral banner (milestones, quiet acknowledgments, undo).
    public var ephemeralBanner: EphemeralBanner?
    /// Backward-compatible alias used by older call sites / tests.
    public var habitMilestoneMessage: String? {
        get { ephemeralBanner?.message }
        set {
            if let newValue {
                showBanner(newValue)
            } else if ephemeralBanner?.undoToken == nil {
                ephemeralBanner = nil
            }
        }
    }
    public private(set) var lastSaveError: String?
    public private(set) var lastSuccessfulSaveAt: Date?
    public var presentEndOfDayReview: Bool = false
    /// True while Settings/Stats/History (or similar) sheet is open from the panel.
    public var isPanelSheetPresented: Bool = false
    /// Bumped to ask the panel to focus the quick-add field (e.g. from the global hotkey).
    public var quickAddFocusSignal: Int = 0
    /// Bumped to ask AppKit to open (or focus) the pop-out Garden window.
    public var openGardenWindowSignal: Int = 0
    /// True while the pop-out Garden window is open. Written only by the AppKit layer.
    public var isGardenWindowOpen: Bool = false

    public private(set) var radioChannels: [SomaFMChannel] = []
    public private(set) var radioSkipChannels: [SomaFMChannel] = []
    public private(set) var radioLoadError: String?
    public private(set) var isRadioLoading = false

    public var thresholds: EscalationThresholds = .gentle

    public init(
        store: DataStore,
        calendar: Calendar = .current,
        remindersProvider: ExternalSourceProvider? = nil,
        moodChecker: MoodAIAvailabilityChecking = LiveMoodAIChecker(),
        schedulesRemindersSync: Bool = true,
        observeSystemEvents: Bool = true
    ) {
        self.store = store
        self.calendar = calendar
        self.moodChecker = moodChecker
        self.schedulesRemindersSync = schedulesRemindersSync
        self.observeSystemEvents = observeSystemEvents
        self.rollover = RolloverEngine(store: store, calendar: calendar)
        self.habitEngine = HabitEngine(store: store, calendar: calendar)
        let provider = remindersProvider ?? RemindersAdapter(calendar: calendar)
        self.remindersSync = RemindersSyncEngine(store: store, provider: provider, calendar: calendar)
        self.habitRemindersSync = HabitRemindersSyncEngine(store: store, provider: provider, calendar: calendar)
        self.remindersLastSyncedAt = remindersSync.lastSyncedAt
        self.remindersSync.loadPersistedPushQueue()
        self.habitRemindersSync.loadPersistedPushQueue()
        self.pomodoro = PomodoroEngine()
        self.radio = RadioPlayerManager(service: somaFM)
        self.pomodoro.onPhaseEnd = { [weak self] phase, elapsed, natural, endedAt in
            self?.handlePhaseEnd(phase, elapsed: elapsed, completedNaturally: natural, endedAt: endedAt)
        }
        self.pomodoro.onStateChange = { [weak self] in self?.syncTickingSound() }
        // Any radio start (play/next/prev/retry/restore/reconnect) silences ticking — the
        // reverse of `syncTickingSound` pausing radio when ticking starts.
        self.radio.onPlaybackStarted = { TickingSoundPlayer.shared.stop() }
        self.notifications.onAuthorizationGranted = { [weak self] in self?.refresh() }
        applyPreferences()
        refreshRemindersAccessStatus()
        refresh()
        if observeSystemEvents { observeSystem() }
    }

    public func refreshRemindersAccessStatus() {
        remindersAccessStatus = remindersSync.accessStatus
    }

    /// Request EventKit access and publish the resulting status for Settings observation.
    @discardableResult
    public func requestRemindersAccess() async -> Bool {
        let granted = await remindersSync.requestAccess()
        refreshRemindersAccessStatus()
        return granted
    }


    private struct PendingUndo {
        enum Kind {
            case undropTodo(UUID)
            case unarchiveHabit(UUID)
            case undoFocusSession(UUID)
        }
        let kind: Kind
    }

    public func showBanner(_ message: String, undoLabel: String? = nil, undoToken: String? = nil) {
        ephemeralBanner = EphemeralBanner(message: message, undoLabel: undoLabel, undoToken: undoToken)
    }

    public func dismissBanner() {
        ephemeralBanner = nil
        pendingUndo = nil
    }

    public func performUndo(token: String) {
        guard let pending = pendingUndo, ephemeralBanner?.undoToken == token else { return }
        switch pending.kind {
        case .undropTodo(let id):
            if let todo = (try? store.allTodos())?.first(where: { $0.id == id }) {
                todo.status = todo.plannedForDate < DayMath.startOfDay(Date(), calendar: calendar) ? .carriedOver : .planned
                commitSave()
                refresh()
            }
        case .unarchiveHabit(let id):
            if let template = try? store.habitTemplate(id: id) {
                template.isActive = true
                commitSave()
                invalidateHabitNotifications()
                refresh()
            }
        case .undoFocusSession(let id):
            if let sessions = try? store.focusSessions(in: Date.distantPast..<Date.distantFuture),
               let session = sessions.first(where: { $0.id == id }) {
                store.context.delete(session)
                commitSave()
                rebuildFocusCache()
            }
        }
        dismissBanner()
    }

    @discardableResult
    private func commitSave() -> Bool {
        let ok = store.save()
        lastSaveError = store.lastSaveError
        lastSuccessfulSaveAt = store.lastSuccessfulSaveAt
        if !ok {
            showBanner("Changes may not be saved")
        }
        return ok
    }

    // MARK: - Derived

    public var overdueCount: Int {
        if Preferences.isAway(on: Date(), calendar: calendar) { return 0 }
        return carriedTodos.filter {
            EscalationModel.countsTowardBadge($0.escalationTier(thresholds: thresholds, calendar: calendar))
        }.count
    }

    public var worstTier: EscalationTier {
        carriedTodos.map { $0.escalationTier(thresholds: thresholds, calendar: calendar) }.max() ?? .onPlan
    }

    public var completedTodayCount: Int { todayTodos.filter(\.isCompleted).count }
    public var inProgressTodayCount: Int { todayTodos.filter(\.isInProgress).count }
    public var totalTodayCount: Int { todayTodos.count }
    public var completedHabitsTodayCount: Int { todayHabits.filter { $0.log.isCompleted }.count }
    public var totalHabitsTodayCount: Int { todayHabits.count }

    // MARK: - Refresh

    /// Reconciles the day (idempotent rollover) and reloads the today/carried lists.
    public func refresh(now: Date = .now) {
        refreshRemindersAccessStatus()
        rollover.performRolloverIfNeeded(now: now)
        habitEngine.materializeIfNeeded(now: now)
        reloadLists(now: now)
        let rawHabits = (try? store.todayHabits(on: now, calendar: calendar)) ?? []
        rebuildHabitCaches(rawHabits: rawHabits, now: now)
        rebuildFocusCache(now: now)
        notifications.updateBacklogNudge(agingCount: overdueCount, now: now, calendar: calendar)
        rescheduleHabitNotificationsIfNeeded(now: now)
        maybePromptEndOfDayReview(now: now)
        scheduleRemindersSync(now: now)
        maybePostWeeklyDigest(now: now)
    }

    public func invalidateRemindersSync() {
        forceRemindersSync = true
    }

    private func markRemindersTodoLocallyModified(_ todo: DailyTodo, now: Date) {
        guard todo.source == .reminders else { return }
        // Do not stamp externalModifiedAt until the push succeeds — otherwise a quit
        // before drain permanently suppresses the corrective pull.
        invalidateRemindersSync()
    }

    private func reloadLists(now: Date) {
        todayTodos = (try? store.todos(on: now, calendar: calendar)) ?? []
        let tomorrow = DayMath.nextDay(now, calendar: calendar)
        tomorrowTodos = (try? store.todos(on: tomorrow, calendar: calendar)) ?? []
        carriedTodos = (try? store.overdueIncompleteTodos(before: now, calendar: calendar)) ?? []
    }

    private func scheduleRemindersSync(now: Date) {
        guard schedulesRemindersSync else { return }
        guard Preferences.remindersSyncEnabled || Preferences.remindersHabitsSyncEnabled else { return }
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
            var changed = false
            if Preferences.remindersSyncEnabled {
                changed = await self.remindersSync.reconcileIfNeeded(now: now, force: force) || changed
            }
            if Preferences.remindersHabitsSyncEnabled {
                changed = await self.habitRemindersSync.reconcileIfNeeded(now: now, force: force) || changed
            }
            self.remindersLastSyncedAt = self.remindersSync.lastSyncedAt
            let errors = [self.remindersSync.lastSyncError, self.habitRemindersSync.lastSyncError]
                .compactMap { $0 }
            self.remindersLastSyncError = errors.isEmpty ? nil : errors.joined(separator: "; ")
            if changed {
                self.reloadLists(now: now)
                let rawHabits = (try? self.store.todayHabits(on: now, calendar: self.calendar)) ?? []
                self.rebuildHabitCaches(rawHabits: rawHabits, now: now)
            }
        }
    }

    // MARK: - Intents

    @discardableResult
    public func addTodo(
        title: String,
        priority: Priority = .medium,
        plannedFor day: Date? = nil,
        now: Date = .now
    ) -> DailyTodo? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let planned = DayMath.startOfDay(day ?? now, calendar: calendar)
        let todo = DailyTodo(
            title: trimmed,
            plannedForDate: planned,
            originalPlannedDate: planned,
            status: .planned,
            priority: priority
        )
        store.insert(todo)
        commitSave()
        if Preferences.remindersPushNewTodos {
            Task { await remindersSync.createReminderForNewTodo(todo, now: now) }
        }
        refresh(now: now)
        return todo
    }

    /// Cycles todo status: to-do → in progress → done → to-do (todos only).
    public func advanceTodo(_ todo: DailyTodo, now: Date = .now) {
        let today = DayMath.startOfDay(now, calendar: calendar)
        switch todo.status {
        case .completed:
            todo.completedDate = nil
            todo.status = todo.plannedForDate < today ? .carriedOver : .planned
        case .inProgress:
            todo.completedDate = now
            todo.status = .completed
            // Keep completed carried-over tasks visible in today's list.
            if todo.plannedForDate < today {
                todo.plannedForDate = today
            }
        case .planned, .carriedOver, .snoozed:
            todo.completedDate = nil
            todo.status = .inProgress
        case .dropped:
            return
        }
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        commitSave()
        refresh(now: now)
    }

    /// Returns a todo to the to-do state from in progress or done.
    public func resetTodo(_ todo: DailyTodo, now: Date = .now) {
        guard todo.status != .dropped else { return }
        todo.completedDate = nil
        let today = DayMath.startOfDay(now, calendar: calendar)
        todo.status = todo.plannedForDate < today ? .carriedOver : .planned
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        commitSave()
        refresh(now: now)
    }

    /// Jumps straight to done (e.g. end-of-day review).
    public func toggleComplete(_ todo: DailyTodo, now: Date = .now) {
        if todo.isCompleted {
            todo.completedDate = nil
            let today = DayMath.startOfDay(now, calendar: calendar)
            todo.status = todo.plannedForDate < today ? .carriedOver : .planned
        } else {
            todo.completedDate = now
            todo.status = .completed
            let today = DayMath.startOfDay(now, calendar: calendar)
            if todo.plannedForDate < today {
                todo.plannedForDate = today
            }
        }
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        commitSave()
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
        commitSave()
        refresh(now: now)
    }

    /// Bring a carried-over task into today (its age is preserved via originalPlannedDate).
    public func reschedule(_ todo: DailyTodo, to day: Date = .now, now: Date = .now) {
        todo.plannedForDate = DayMath.startOfDay(day, calendar: calendar)
        todo.snoozedUntil = nil
        todo.completedDate = nil
        todo.status = .planned
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        commitSave()
        refresh(now: now)
    }

    public func drop(_ todo: DailyTodo, now: Date = .now) {
        todo.status = .dropped
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        commitSave()
        refresh(now: now)
        let token = todo.id.uuidString
        pendingUndo = PendingUndo(kind: .undropTodo(todo.id))
        showBanner("Task dropped", undoLabel: "Undo", undoToken: token)
    }

    public func setPriority(_ todo: DailyTodo, _ priority: Priority, now: Date = .now) {
        guard todo.priority != priority else { return }
        todo.priority = priority
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        commitSave()
        refresh(now: now)
    }

    /// Rename a task. No-op for an empty/whitespace or unchanged title.
    public func rename(_ todo: DailyTodo, to title: String, now: Date = .now) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != todo.title else { return }
        todo.title = trimmed
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        commitSave()
        refresh(now: now)
    }

    /// Update the task description (`notes`). Trims trailing whitespace; empty is allowed.
    public func updateNotes(_ todo: DailyTodo, to notes: String, now: Date = .now) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != todo.notes else { return }
        todo.notes = trimmed
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        commitSave()
        refresh(now: now)
    }

    // MARK: - Checklist

    public func checklistItems(for todo: DailyTodo) -> [TodoChecklistItem] {
        (try? store.checklistItems(for: todo.id)) ?? []
    }

    @discardableResult
    public func addChecklistItem(to todo: DailyTodo, title: String, now: Date = .now) -> TodoChecklistItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextOrder = (checklistItems(for: todo).map(\.sortOrder).max() ?? -1) + 1
        let item = TodoChecklistItem(todoId: todo.id, title: trimmed, sortOrder: nextOrder)
        store.insert(item)
        commitSave()
        refresh(now: now)
        return item
    }

    public func renameChecklistItem(_ item: TodoChecklistItem, to title: String, now: Date = .now) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.title else { return }
        item.title = trimmed
        commitSave()
        refresh(now: now)
    }

    public func toggleChecklistItem(_ item: TodoChecklistItem, now: Date = .now) {
        item.isCompleted.toggle()
        commitSave()
        refresh(now: now)
    }

    public func deleteChecklistItem(_ item: TodoChecklistItem, now: Date = .now) {
        store.delete(item)
        commitSave()
        refresh(now: now)
    }

    public func moveChecklistItem(_ item: TodoChecklistItem, to sortOrder: Int, now: Date = .now) {
        guard item.sortOrder != sortOrder else { return }
        item.sortOrder = sortOrder
        commitSave()
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
        schedulePreset: HabitSchedulePreset = .everyDay,
        scheduleWeekdayMask: Int = HabitSchedule.allDaysMask,
        remindersSyncEnabled: Bool = false,
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
            notifyEnabled: notifyEnabled,
            schedulePresetRaw: schedulePreset.rawValue,
            scheduleWeekdayMask: scheduleWeekdayMask,
            remindersSyncEnabled: remindersSyncEnabled
        )
        store.insert(template)
        commitSave()
        if remindersSyncEnabled {
            markHabitLocallyModified(template, now: now)
            habitRemindersSync.enqueuePush(for: template)
            invalidateRemindersSync()
        }
        invalidateHabitNotifications()
        refresh(now: now)
        return template
    }

    public func updateHabitTemplate(_ template: HabitTemplate, now: Date = .now) {
        if template.remindersSyncEnabled {
            markHabitLocallyModified(template, now: now)
            habitRemindersSync.enqueuePush(for: template)
        } else if template.externalReminderIdentifier != nil {
            // Opting out must clear the link so remote edits cannot overwrite local state.
            template.externalReminderIdentifier = nil
            template.remindersCalendarIdentifier = nil
            template.externalModifiedAt = nil
        }
        commitSave()
        invalidateHabitNotifications()
        refresh(now: now)
    }

    public func archiveHabitTemplate(_ template: HabitTemplate, now: Date = .now) {
        template.isActive = false
        if template.remindersSyncEnabled || template.externalReminderIdentifier != nil {
            markHabitLocallyModified(template, now: now)
            habitRemindersSync.enqueuePush(for: template)
        }
        commitSave()
        invalidateHabitNotifications()
        refresh(now: now)
        let token = template.id.uuidString
        pendingUndo = PendingUndo(kind: .unarchiveHabit(template.id))
        showBanner("Habit archived", undoLabel: "Undo", undoToken: token)
    }

    public func unarchiveHabitTemplate(_ template: HabitTemplate, now: Date = .now) {
        template.isActive = true
        commitSave()
        invalidateHabitNotifications()
        refresh(now: now)
    }

    /// Disable Reminders sync for a habit and clear the external link so pulls cannot overwrite it.
    public func disableHabitRemindersSync(_ template: HabitTemplate, now: Date = .now) {
        template.remindersSyncEnabled = false
        template.externalReminderIdentifier = nil
        template.remindersCalendarIdentifier = nil
        template.externalModifiedAt = nil
        commitSave()
        refresh(now: now)
    }

    public func toggleHabit(_ log: HabitLog, now: Date = .now) {
        let priorStreak = habitStreakEntries.first(where: { $0.template.id == log.templateId })?.streak.current ?? 0
        if log.isCompleted {
            log.completedAt = nil
            log.status = .pending
            ephemeralBanner = nil
        } else if log.status == .skipped {
            // "Mark incomplete" on a skipped habit returns it to pending — never completes it.
            log.completedAt = nil
            log.status = .pending
        } else {
            log.completedAt = now
            log.status = .completed
            let newStreak = priorStreak + 1
            if HabitAnalytics.isMilestone(newStreak), newStreak > priorStreak,
               let title = todayHabits.first(where: { $0.log.id == log.id })?.template.title {
                showBanner("\(newStreak) days of “\(title)” — keep going.")
            }
        }
        commitSave()
        if let template = try? store.habitTemplate(id: log.templateId), template.remindersSyncEnabled {
            markHabitLocallyModified(template, now: now)
            habitRemindersSync.enqueuePush(for: template)
            invalidateRemindersSync()
        }
        invalidateHabitNotifications()
        refresh(now: now)
    }

    public func skipHabit(_ log: HabitLog, now: Date = .now) {
        log.completedAt = nil
        log.status = .skipped
        commitSave()
        invalidateHabitNotifications()
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

    public func focusStreak() -> FocusStreakEntry? {
        focusStreakEntry
    }

    /// Clears the notification debounce so the next `refresh()` reschedules habit anchors.
    public func invalidateHabitNotifications() {
        lastHabitNotifySignature = nil
    }

    private func rebuildFocusCache(now: Date = .now) {
        let today = calendar.startOfDay(for: now)
        let lookbackStart = calendar.date(
            byAdding: .day, value: -FocusAnalytics.cacheLookbackDays, to: today
        ) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let sessions = (try? store.focusSessions(in: lookbackStart..<end)) ?? []
        focusStreakEntry = FocusAnalytics.entry(sessions: sessions, asOf: now, calendar: calendar)
        settleGarden(sessions: sessions, now: now)
    }

    private func settleGarden(sessions: [FocusSession], now: Date) {
        guard let meta = try? store.gardenMeta() else {
            gardenSnapshot = nil
            return
        }
        let priorLifetime = meta.lifetimeCompletedSessions
        let snapshot = GardenEngine.settle(
            meta: meta,
            sessions: sessions,
            asOf: now,
            calendar: calendar,
            mode: Preferences.gardenActionMode
        )
        gardenSnapshot = snapshot
        commitSave()
        let grew = meta.lifetimeCompletedSessions > priorLifetime
        if grew || snapshot.justHarvestedCropID != nil {
            playGardenFeedbackIfEnabled(now: now)
        }
    }

    private func playGardenFeedbackIfEnabled(now: Date) {
        guard Preferences.soundEnabled, Preferences.gardenSoundEnabled else { return }
        guard Preferences.shouldPlayAudibleAlerts(now: now, calendar: calendar) else { return }
        AlertSoundPlayer.shared.playGardenChime()
    }

    /// Purchase a garden shop item; returns whether the purchase succeeded.
    @discardableResult
    public func purchaseGardenItem(_ itemID: String) -> Bool {
        guard let meta = try? store.gardenMeta() else { return false }
        let result = GardenShop.purchase(itemID: itemID, meta: meta)
        if result.success {
            commitSave()
            rebuildFocusCache()
        }
        return result.success
    }

    /// Manually harvest a mature plot (Manual garden mode). Returns whether it acted.
    /// The re-settle after this has `newEnergy == 0`, so the chime won't fire from `settleGarden` —
    /// this intent plays it directly.
    @discardableResult
    public func harvestGardenSlot(_ index: Int, now: Date = .now) -> Bool {
        guard let meta = try? store.gardenMeta() else { return false }
        guard GardenEngine.harvest(meta: meta, slotIndex: index, asOf: now, calendar: calendar) != nil else {
            return false
        }
        commitSave()
        rebuildFocusCache(now: now)
        playGardenFeedbackIfEnabled(now: now)
        return true
    }

    /// Manually plant an empty plot (Manual garden mode). Returns whether it acted.
    @discardableResult
    public func plantGardenSlot(_ index: Int, now: Date = .now) -> Bool {
        guard let meta = try? store.gardenMeta() else { return false }
        guard GardenEngine.plant(meta: meta, slotIndex: index, asOf: now, calendar: calendar) != nil else {
            return false
        }
        commitSave()
        rebuildFocusCache(now: now)
        playGardenFeedbackIfEnabled(now: now)
        return true
    }

    /// Buy a farm animal from the shop. Returns whether the purchase succeeded.
    @discardableResult
    public func buyAnimal(_ kind: AnimalKind, now: Date = .now) -> Bool {
        guard let meta = try? store.gardenMeta() else { return false }
        guard GardenShop.buyAnimal(kind: kind, meta: meta, asOf: now).success else { return false }
        commitSave()
        rebuildFocusCache(now: now)
        playGardenFeedbackIfEnabled(now: now)
        return true
    }

    /// Collect the ready product from an owned animal. Returns whether it acted.
    /// The re-settle after this has `newEnergy == 0`, so the chime won't fire from `settleGarden` —
    /// this intent plays it directly (mirrors `harvestGardenSlot`).
    @discardableResult
    public func collectFromAnimal(_ id: UUID, now: Date = .now) -> Bool {
        guard let meta = try? store.gardenMeta() else { return false }
        guard GardenEngine.collectFromAnimal(meta: meta, animalID: id, asOf: now, calendar: calendar) != nil else {
            return false
        }
        commitSave()
        rebuildFocusCache(now: now)
        playGardenFeedbackIfEnabled(now: now)
        return true
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
                logs: logs, template: template, asOf: now, calendar: calendar
            )
            let heatmap = HabitAnalytics.heatmap(
                logs: logs, template: template, days: 28, endingAt: now, calendar: calendar
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

    private func markHabitLocallyModified(_ template: HabitTemplate, now: Date) {
        // Stamp only after successful push (HabitRemindersSyncEngine).
        _ = now
        _ = template
    }

    private func rescheduleHabitNotificationsIfNeeded(now: Date = .now) {
        let templates = ((try? store.activeHabitTemplates()) ?? [])
            .filter { $0.isScheduled(on: now, calendar: calendar) }
        let logs = (try? store.habitLogs(on: now, calendar: calendar)) ?? []
        let signature = HabitNotifySignature.make(
            templates: templates,
            todayLogs: logs,
            habitNotifyEnabled: Preferences.habitNotifyEnabled
        )
        guard signature != lastHabitNotifySignature else { return }
        lastHabitNotifySignature = signature
        notifications.rescheduleHabitAnchors(templates: templates, todayLogs: logs, now: now, calendar: calendar)
    }

    /// Stop the current Pomodoro session (records elapsed focus time via onPhaseEnd).
    public func stopPomodoro(now: Date = .now) {
        guard pomodoro.phase != .idle else { return }
        let wasWork = pomodoro.phase == .work
        pomodoro.stop(now: now)
        if wasWork {
            // handlePhaseEnd already inserted FocusSession; offer undo for a few seconds.
            if let session = (try? store.focusSessions(
                in: now.addingTimeInterval(-2)..<now.addingTimeInterval(2)
            ))?.last {
                let token = session.id.uuidString
                pendingUndo = PendingUndo(kind: .undoFocusSession(session.id))
                showBanner("Focus session stopped", undoLabel: "Undo", undoToken: token)
                return
            }
        }
        showBanner("Focus session stopped")
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

    // MARK: - Lofi Radio

    public func loadRadioChannels() async {
        guard !isRadioLoading else { return }
        isRadioLoading = true
        radioLoadError = nil
        defer { isRadioLoading = false }
        do {
            let all = try await somaFM.fetchCuratedChannels()
            radioChannels = all
            radioSkipChannels = SomaFMCuratedChannels.filterSkip(all)
            radio.refreshNowPlaying(from: all)
            await prefetchAdjacentPLS()
        } catch {
            radioLoadError = "Can't reach SomaFM. Check your connection."
            print("DayBar: radio channel load failed: \(error)")
        }
    }

    public func playRadio(_ channel: SomaFMChannel) async {
        await radio.play(channel: channel)
        await prefetchAdjacent(for: channel)
    }

    public func radioNextChannel() async {
        await radio.playNextChannel(in: radioSkipChannels)
        if let channel = radio.currentChannel {
            await prefetchAdjacent(for: channel)
        }
    }

    public func radioPreviousChannel() async {
        await radio.playPreviousChannel(in: radioSkipChannels)
        if let channel = radio.currentChannel {
            await prefetchAdjacent(for: channel)
        }
    }

    public func toggleRadio() async {
        if radio.isPlaying {
            radio.pause()
            // Radio stopping frees the "one audio at a time" slot: resume ticking if a
            // focus session is still running and the user has it enabled.
            syncTickingSound()
            return
        }
        if let channel = radio.currentChannel {
            await playRadio(channel)
            return
        }
        guard let channel = radioSkipChannels.randomElement() ?? radioChannels.randomElement() else { return }
        await playRadio(channel)
    }

    public func restoreRadioSession() async {
        await loadRadioChannels()
        await radio.restoreSession(channels: radioChannels)
    }

    public func artworkData(for channel: SomaFMChannel) async -> Data? {
        await artworkCache.imageData(for: channel)
    }

    private func prefetchAdjacentPLS() async {
        let id = Preferences.radioLastChannelID ?? SomaFMCuratedChannels.curatedSkipIDs.first
        let list = radioSkipChannels.isEmpty ? radioChannels : radioSkipChannels
        guard let id, let channel = list.first(where: { $0.id == id }) ?? list.first else { return }
        await prefetchAdjacent(for: channel)
    }

    private func prefetchAdjacent(for channel: SomaFMChannel) async {
        let list = radioSkipChannels.isEmpty ? radioChannels : radioSkipChannels
        var targets: [SomaFMChannel] = [channel]
        if let next = SomaFMCuratedChannels.adjacentChannel(from: channel, in: list, direction: .next) {
            targets.append(next)
        }
        if let prev = SomaFMCuratedChannels.adjacentChannel(from: channel, in: list, direction: .previous) {
            targets.append(prev)
        }
        await somaFM.prefetchStreamURLs(for: targets)
    }

    /// Rebuild the Pomodoro configuration from saved Preferences (call after a Settings change).
    public func applyPreferences() {
        pomodoro.config = Preferences.pomodoroConfig
        thresholds = Preferences.escalationThresholds
        syncTickingSound()
    }

    // MARK: - Ticking sound

    /// Keeps the ambient ticking sound in sync with the Pomodoro state and the user's
    /// preference. Mutually exclusive with Lofi Radio: starting ticking pauses radio here,
    /// and starting radio stops ticking via `radio.onPlaybackStarted` (wired in `init`).
    public func syncTickingSound() {
        let shouldTick = TickingSoundGate.shouldPlay(
            preferenceEnabled: Preferences.tickingSoundEnabled,
            isWorkPhase: pomodoro.phase == .work,
            isRunning: pomodoro.isRunning
        )
        if shouldTick {
            if radio.isPlaying { radio.pause() }
            TickingSoundPlayer.shared.start()
        } else {
            TickingSoundPlayer.shared.stop()
        }
    }

    // MARK: - Analytics

    public func statBuckets(granularity: Granularity, count: Int, now: Date = .now) -> [StatBucket] {
        let range = Analytics.range(endingAt: now, count: count, granularity: granularity, calendar: calendar)
        let todos = (try? store.todos(plannedIn: range)) ?? []
        let sessions = (try? store.focusSessions(in: range)) ?? []
        return Analytics.buckets(todos: todos, sessions: sessions, endingAt: now, count: count, granularity: granularity, calendar: calendar)
    }

    public func moodStatBuckets(granularity: Granularity, count: Int, now: Date = .now) -> [MoodStatBucket] {
        let range = Analytics.range(endingAt: now, count: count, granularity: granularity, calendar: calendar)
        let dayLogs = (try? store.dayLogs(in: range)) ?? []
        return MoodAnalytics.buckets(dayLogs: dayLogs, endingAt: now, count: count, granularity: granularity, calendar: calendar)
    }

    /// Completed tasks grouped by finish day, newest first.
    public func completedHistory(days: Int = 30, now: Date = .now) -> [DayHistoryGroup] {
        let dayCount = max(1, days)
        let end = calendar.date(byAdding: .day, value: 1, to: DayMath.startOfDay(now, calendar: calendar)) ?? now
        let start = calendar.date(byAdding: .day, value: -dayCount, to: DayMath.startOfDay(now, calendar: calendar)) ?? now
        let todos = (try? store.completedTodos(in: start..<end)) ?? []
        var groups: [Date: [DailyTodo]] = [:]
        for todo in todos {
            guard let completed = todo.completedDate else { continue }
            let day = DayMath.startOfDay(completed, calendar: calendar)
            groups[day, default: []].append(todo)
        }
        return groups
            .map { day, todos in
                DayHistoryGroup(
                    date: day,
                    todos: todos.sorted {
                        ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast)
                    }
                )
            }
            .sorted { $0.date > $1.date }
    }

    public static let completedHistoryDays = 30

    public func completedHistoryTotal(days: Int = 30, now: Date = .now) -> Int {
        completedHistory(days: days, now: now).reduce(0) { $0 + $1.count }
    }

    /// Average completions per calendar day across the window (not only days with activity).
    public func completedHistoryAveragePerDay(days: Int = 30, now: Date = .now) -> Int {
        completedHistoryTotal(days: days, now: now) / max(1, days)
    }

    // MARK: - End-of-day review

    public func hasReviewedToday(now: Date = .now) -> Bool {
        store.hasDayLog(on: now, calendar: calendar)
    }

    public func saveDayLog(reflection: String, moodTag: MoodTag? = nil, moodSource: MoodSource = .none, now: Date = .now) {
        store.upsertDayLog(
            day: now,
            reflection: reflection,
            plannedCount: totalTodayCount,
            completedCount: completedTodayCount,
            moodTag: moodTag,
            moodSource: moodSource,
            calendar: calendar
        )
        presentEndOfDayReview = false
    }

    /// Snoozes the auto-popup for an hour — used by the review sheet's "Not now" button.
    /// Does not affect opening it manually via "Review day…".
    public func snoozeEndOfDayReview(now: Date = .now) {
        reviewSnoozedUntil = now.addingTimeInterval(3600)
        presentEndOfDayReview = false
    }

    /// - Parameter focusSessionRunning: overrides the live engine check. Needed when called
    ///   from `handlePhaseEnd`'s work-end path, which runs inside `onPhaseEnd` *before* the
    ///   engine clears `endDate`/`phase` — so the live check would still report the just-ended
    ///   session as running and wrongly suppress the retry.
    private func maybePromptEndOfDayReview(now: Date = .now, focusSessionRunning: Bool? = nil) {
        guard !presentEndOfDayReview else { return }
        let running = focusSessionRunning ?? (pomodoro.phase == .work && pomodoro.isRunning)
        let shouldPresent = EndOfDayReviewGate.shouldPresent(
            hasReviewedToday: hasReviewedToday(now: now),
            totalTodayCount: totalTodayCount,
            now: now,
            eveningTime: Preferences.eveningTime(on: now, calendar: calendar),
            snoozedUntil: reviewSnoozedUntil,
            isFocusSessionRunning: running
        )
        if shouldPresent { presentEndOfDayReview = true }
    }

    private func maybePostWeeklyDigest(now: Date) {
        guard Preferences.weeklyDigestEnabled else { return }
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday
        guard weekday == 1 else { return }
        let today = DayMath.startOfDay(now, calendar: calendar)
        if let last = Preferences.weeklyDigestLastFiredDay, calendar.isDate(last, inSameDayAs: today) {
            return
        }
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let nextDay = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let completed = (try? store.completedTodos(in: weekStart..<nextDay))?.count ?? 0
        let habitLogs = (try? store.habitLogs(in: weekStart..<nextDay)) ?? []
        let habitsDone = habitLogs.filter(\.isCompleted).count
        let focus = (try? store.focusSessions(in: weekStart..<nextDay))?.count ?? 0
        notifications.postWeeklyDigest(
            tasksCompleted: completed,
            habitsCompleted: habitsDone,
            focusSessions: focus,
            agingTasks: overdueCount
        )
        Preferences.weeklyDigestLastFiredDay = today
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

        let tzChange = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.calendar = .current
                self.rollover.calendar = self.calendar
                self.habitEngine.calendar = self.calendar
                self.refresh()
            }
        }
        observers.append(tzChange)

        notifications.onAuthorizationGranted = { [weak self] in
            self?.refresh()
        }

        let remindersChange = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateRemindersSync()
                self?.refresh()
            }
        }
        observers.append(remindersChange)

        let idlePoll = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateIdleBreakSkip() }
        }
        idlePoll.tolerance = 5
        RunLoop.main.add(idlePoll, forMode: .common)
        idlePollTimer = idlePoll
    }

    /// When a break is armed (waiting for play) and the user has been away long enough,
    /// skip the break and start the next focus session.
    func evaluateIdleBreakSkip(now: Date = .now) {
        guard Preferences.skipBreakWhenIdle else { return }
        guard pomodoro.phase.isBreak else {
            breakArmedAt = nil
            return
        }
        // Only auto-skip when the user forgot to press play — not during an active break.
        guard !pomodoro.isRunning else { return }
        let threshold = TimeInterval(Preferences.idleSkipMinutes * 60)
        let idleSinceInput = IdleMonitor.secondsSinceLastInput()
        let sinceBreak = now.timeIntervalSince(breakArmedAt ?? now)
        guard idleSinceInput >= threshold, sinceBreak >= threshold else { return }
        skipBreakAndStartWork(now: now, silent: true)
        showBanner("You were away — started your next focus session")
    }

    /// Skip the current break and immediately start the next focus session.
    public func skipBreakAndStartWork(now: Date = .now, silent: Bool = false) {
        guard pomodoro.phase.isBreak else { return }
        if silent { suppressNextPhaseEndFeedback = true }
        pomodoro.skip(now: now)
        pomodoro.start(.work, now: now)
        breakArmedAt = nil
    }

    private func handleWake() {
        pomodoro.tick()
        refresh()
    }

    private func handlePhaseEnd(_ phase: PomodoroPhase, elapsed: TimeInterval, completedNaturally: Bool, endedAt: Date) {
        var focusMilestoneBanner: String?
        if phase == .work {
            let minutes = Int((elapsed / 60).rounded())
            if minutes > 0 {
                let priorStreak = focusStreakEntry?.streak.current ?? 0
                store.insert(FocusSession(endedAt: endedAt, minutes: minutes, completed: completedNaturally))
                commitSave()
                rebuildFocusCache(now: endedAt)
                if completedNaturally {
                    let newStreak = focusStreakEntry?.streak.current ?? 0
                    if FocusAnalytics.isMilestone(newStreak), newStreak > priorStreak {
                        focusMilestoneBanner = "\(newStreak) days of focus — keep going."
                    }
                }
            }
            breakArmedAt = endedAt
            // The recap sheet is held back while a focus session runs — retry immediately
            // now that it just ended, instead of waiting for the next panel open. The engine
            // hasn't cleared its "running" state yet at this point, so tell the gate the
            // focus session is over explicitly.
            maybePromptEndOfDayReview(now: endedAt, focusSessionRunning: false)
        } else if phase.isBreak {
            breakArmedAt = nil
        }
        guard !suppressNextPhaseEndFeedback else {
            suppressNextPhaseEndFeedback = false
            return
        }
        if Preferences.soundEnabled, Preferences.shouldPlayAudibleAlerts(now: endedAt, calendar: calendar) {
            AlertSoundPlayer.shared.playPhaseEndRing()
        }
        notifications.postPhaseEndBanner(finished: phase)
        let shouldPauseRadio = phase == .work && radio.isPlaying && Preferences.radioPauseOnFocusEnd
        if shouldPauseRadio {
            radio.pause()
        }
        if let focusMilestoneBanner {
            showBanner(focusMilestoneBanner)
        } else if shouldPauseRadio {
            showBanner("Focus ended — music paused")
        }
    }
}
