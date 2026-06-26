import Foundation
import Observation
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

    @ObservationIgnored private let rollover: RolloverEngine
    @ObservationIgnored private let habitEngine: HabitEngine
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    public private(set) var todayTodos: [DailyTodo] = []
    public private(set) var carriedTodos: [DailyTodo] = []
    public private(set) var todayHabits: [TodayHabit] = []
    /// Ephemeral banner after hitting a streak milestone (7/30/100 days).
    public var habitMilestoneMessage: String?
    public var isPanelPresented: Bool = false
    public var presentEndOfDayReview: Bool = false
    /// Bumped to ask the panel to focus the quick-add field (e.g. from the global hotkey).
    public var quickAddFocusSignal: Int = 0

    public var thresholds: EscalationThresholds = .gentle

    public init(store: DataStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
        self.rollover = RolloverEngine(store: store, calendar: calendar)
        self.habitEngine = HabitEngine(store: store, calendar: calendar)
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
        todayTodos = (try? store.todos(on: now, calendar: calendar)) ?? []
        carriedTodos = (try? store.overdueIncompleteTodos(before: now, calendar: calendar)) ?? []
        todayHabits = (try? store.todayHabits(on: now, calendar: calendar)) ?? []
        notifications.updateBacklogNudge(agingCount: overdueCount, now: now, calendar: calendar)
        rescheduleHabitNotifications(now: now)
        maybePromptEndOfDayReview(now: now)
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
        store.save()
        refresh(now: now)
    }

    /// Bring a carried-over task into today (its age is preserved via originalPlannedDate).
    public func reschedule(_ todo: DailyTodo, to day: Date = .now, now: Date = .now) {
        todo.plannedForDate = DayMath.startOfDay(day, calendar: calendar)
        todo.snoozedUntil = nil
        todo.status = .planned
        store.save()
        refresh(now: now)
    }

    public func drop(_ todo: DailyTodo, now: Date = .now) {
        todo.status = .dropped
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
        refresh(now: now)
        return template
    }

    public func updateHabitTemplate(_ template: HabitTemplate, now: Date = .now) {
        store.save()
        refresh(now: now)
    }

    public func archiveHabitTemplate(_ template: HabitTemplate, now: Date = .now) {
        template.isActive = false
        store.save()
        refresh(now: now)
    }

    public func toggleHabit(_ log: HabitLog, now: Date = .now) {
        let priorStreak = streak(for: log.templateId, now: now)
        if log.isCompleted {
            log.completedAt = nil
            log.status = .pending
            habitMilestoneMessage = nil
        } else {
            log.completedAt = now
            log.status = .completed
            let newStreak = streak(for: log.templateId, now: now)
            if HabitAnalytics.isMilestone(newStreak), newStreak > priorStreak,
               let title = todayHabits.first(where: { $0.log.id == log.id })?.template.title {
                habitMilestoneMessage = "\(newStreak) days of “\(title)” — keep going."
            }
        }
        store.save()
        refresh(now: now)
    }

    public func skipHabit(_ log: HabitLog, now: Date = .now) {
        log.completedAt = nil
        log.status = .skipped
        store.save()
        refresh(now: now)
    }

    public func streak(for templateId: UUID, now: Date = .now) -> Int {
        let logs = (try? store.allHabitLogs()) ?? []
        return HabitAnalytics.streakInfo(logs: logs, templateId: templateId, asOf: now, calendar: calendar).current
    }

    public func habitStatBuckets(granularity: Granularity, count: Int, now: Date = .now) -> [HabitStatBucket] {
        let range = Analytics.range(endingAt: now, count: count, granularity: granularity, calendar: calendar)
        let logs = (try? store.habitLogs(in: range)) ?? []
        return HabitAnalytics.buckets(logs: logs, endingAt: now, count: count, granularity: granularity, calendar: calendar)
    }

    public func habitHeatmap(templateId: UUID, days: Int = 28, now: Date = .now) -> [HabitHeatmapCell] {
        let logs = (try? store.allHabitLogs()) ?? []
        return HabitAnalytics.heatmap(logs: logs, templateId: templateId, days: days, endingAt: now, calendar: calendar)
    }

    public func habitStreaks(now: Date = .now) -> [(template: HabitTemplate, streak: StreakInfo)] {
        let templates = (try? store.activeHabitTemplates()) ?? []
        let logs = (try? store.allHabitLogs()) ?? []
        return templates.map { template in
            let info = HabitAnalytics.streakInfo(logs: logs, templateId: template.id, asOf: now, calendar: calendar)
            return (template, info)
        }
    }

    private func rescheduleHabitNotifications(now: Date = .now) {
        let templates = (try? store.activeHabitTemplates()) ?? []
        let logs = (try? store.habitLogs(on: now, calendar: calendar)) ?? []
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
