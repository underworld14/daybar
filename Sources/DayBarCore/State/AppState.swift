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

    @ObservationIgnored private let rollover: RolloverEngine
    @ObservationIgnored private let habitEngine: HabitEngine
    @ObservationIgnored private let somaFM = SomaFMService()
    @ObservationIgnored private let artworkCache = RadioArtworkCache()
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var lastHabitNotifySignature: String?
    @ObservationIgnored private var forceRemindersSync = false
    @ObservationIgnored private var pendingRemindersSync = false
    @ObservationIgnored private var remindersSyncTask: Task<Void, Never>?
    @ObservationIgnored private let schedulesRemindersSync: Bool
    @ObservationIgnored private let observeSystemEvents: Bool
    @ObservationIgnored private var breakArmedAt: Date?
    @ObservationIgnored private var idlePollTimer: Timer?

    public private(set) var remindersLastSyncedAt: Date?
    public private(set) var remindersLastSyncError: String?
    public private(set) var isRemindersSyncing = false

    public private(set) var todayTodos: [DailyTodo] = []
    public private(set) var tomorrowTodos: [DailyTodo] = []
    public private(set) var carriedTodos: [DailyTodo] = []
    public private(set) var todayHabits: [TodayHabit] = []
    public private(set) var habitStreakEntries: [HabitStreakEntry] = []
    /// Ephemeral banner after hitting a streak milestone (7/30/100 days).
    public var habitMilestoneMessage: String?
    public var isPanelPresented: Bool = false
    public var presentEndOfDayReview: Bool = false
    /// Bumped to ask the panel to focus the quick-add field (e.g. from the global hotkey).
    public var quickAddFocusSignal: Int = 0

    public private(set) var radioChannels: [SomaFMChannel] = []
    public private(set) var radioSkipChannels: [SomaFMChannel] = []
    public private(set) var radioLoadError: String?
    public private(set) var isRadioLoading = false

    public var thresholds: EscalationThresholds = .gentle

    public init(
        store: DataStore,
        calendar: Calendar = .current,
        remindersProvider: ExternalSourceProvider? = nil,
        schedulesRemindersSync: Bool = true,
        observeSystemEvents: Bool = true
    ) {
        self.store = store
        self.calendar = calendar
        self.schedulesRemindersSync = schedulesRemindersSync
        self.observeSystemEvents = observeSystemEvents
        self.rollover = RolloverEngine(store: store, calendar: calendar)
        self.habitEngine = HabitEngine(store: store, calendar: calendar)
        let provider = remindersProvider ?? RemindersAdapter(calendar: calendar)
        self.remindersSync = RemindersSyncEngine(store: store, provider: provider, calendar: calendar)
        self.habitRemindersSync = HabitRemindersSyncEngine(store: store, provider: provider, calendar: calendar)
        self.remindersLastSyncedAt = remindersSync.lastSyncedAt
        self.pomodoro = PomodoroEngine()
        self.radio = RadioPlayerManager(service: somaFM)
        self.pomodoro.onPhaseEnd = { [weak self] phase, elapsed, natural, endedAt in
            self?.handlePhaseEnd(phase, elapsed: elapsed, completedNaturally: natural, endedAt: endedAt)
        }
        applyPreferences()
        refresh()
        if observeSystemEvents { observeSystem() }
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
    public var inProgressTodayCount: Int { todayTodos.filter(\.isInProgress).count }
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
        store.save()
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
        case .planned, .carriedOver, .snoozed:
            todo.completedDate = nil
            todo.status = .inProgress
        case .dropped:
            return
        }
        markRemindersTodoLocallyModified(todo, now: now)
        remindersSync.enqueuePush(for: todo)
        store.save()
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
        store.save()
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
        todo.completedDate = nil
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
        store.save()
        if remindersSyncEnabled {
            markHabitLocallyModified(template, now: now)
            habitRemindersSync.enqueuePush(for: template)
        }
        invalidateHabitNotifications()
        refresh(now: now)
        return template
    }

    public func updateHabitTemplate(_ template: HabitTemplate, now: Date = .now) {
        if template.remindersSyncEnabled {
            markHabitLocallyModified(template, now: now)
            habitRemindersSync.enqueuePush(for: template)
        }
        store.save()
        invalidateHabitNotifications()
        refresh(now: now)
    }

    public func archiveHabitTemplate(_ template: HabitTemplate, now: Date = .now) {
        template.isActive = false
        if template.remindersSyncEnabled || template.externalReminderIdentifier != nil {
            markHabitLocallyModified(template, now: now)
            habitRemindersSync.enqueuePush(for: template)
        }
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
        if let template = try? store.habitTemplate(id: log.templateId), template.remindersSyncEnabled {
            markHabitLocallyModified(template, now: now)
            habitRemindersSync.enqueuePush(for: template)
            invalidateRemindersSync()
        }
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
        template.externalModifiedAt = now
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
        await radio.togglePlayPause()
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
    }

    // MARK: - Analytics

    public func statBuckets(granularity: Granularity, count: Int, now: Date = .now) -> [StatBucket] {
        let range = Analytics.range(endingAt: now, count: count, granularity: granularity, calendar: calendar)
        let todos = (try? store.todos(plannedIn: range)) ?? []
        let sessions = (try? store.focusSessions(in: range)) ?? []
        return Analytics.buckets(todos: todos, sessions: sessions, endingAt: now, count: count, granularity: granularity, calendar: calendar)
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
            .map { DayHistoryGroup(date: $0.key, todos: $0.value) }
            .sorted { $0.date > $1.date }
    }

    public var completedHistoryTotal: Int {
        completedHistory().reduce(0) { $0 + $1.count }
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

        let idlePoll = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateIdleBreakSkip() }
        }
        idlePoll.tolerance = 5
        RunLoop.main.add(idlePoll, forMode: .common)
        idlePollTimer = idlePoll
    }

    /// When a break is armed or running and the user has been away long enough, skip the
    /// break and start the next focus session.
    func evaluateIdleBreakSkip(now: Date = .now) {
        guard Preferences.skipBreakWhenIdle else { return }
        guard pomodoro.phase.isBreak else {
            breakArmedAt = nil
            return
        }
        let threshold = TimeInterval(Preferences.idleSkipMinutes * 60)
        let idleSinceInput = IdleMonitor.secondsSinceLastInput()
        let sinceBreak = now.timeIntervalSince(breakArmedAt ?? now)
        guard idleSinceInput >= threshold, sinceBreak >= threshold else { return }
        skipBreakAndStartWork(now: now)
    }

    /// Skip the current break and immediately start the next focus session.
    public func skipBreakAndStartWork(now: Date = .now) {
        guard pomodoro.phase.isBreak else { return }
        pomodoro.skip(now: now)
        pomodoro.start(.work, now: now)
        breakArmedAt = nil
    }

    private func handleWake() {
        pomodoro.tick()
        refresh()
    }

    private func handlePhaseEnd(_ phase: PomodoroPhase, elapsed: TimeInterval, completedNaturally: Bool, endedAt: Date) {
        if phase == .work {
            let minutes = Int((elapsed / 60).rounded())
            if minutes > 0 {
                store.insert(FocusSession(endedAt: endedAt, minutes: minutes, completed: completedNaturally))
                store.save()
            }
            breakArmedAt = endedAt
        } else if phase.isBreak {
            breakArmedAt = nil
        }
        #if canImport(AppKit)
        if Preferences.soundEnabled { AppKitBridge.playPhaseEndSound(named: Preferences.soundName) }
        #endif
        notifications.postPhaseEndBanner(finished: phase)
        if phase == .work, radio.isPlaying, Preferences.radioPauseOnFocusEnd {
            radio.pause()
            habitMilestoneMessage = "Focus ended — music paused"
        }
    }
}
