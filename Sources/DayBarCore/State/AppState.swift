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

    @ObservationIgnored private let rollover: RolloverEngine
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    public private(set) var todayTodos: [DailyTodo] = []
    public private(set) var carriedTodos: [DailyTodo] = []
    public var isPanelPresented: Bool = false

    public var thresholds: EscalationThresholds = .gentle

    public init(store: DataStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
        self.rollover = RolloverEngine(store: store, calendar: calendar)
        self.pomodoro = PomodoroEngine()
        self.pomodoro.onPhaseEnd = { [weak self] phase in self?.handlePhaseEnd(phase) }
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

    // MARK: - Refresh

    /// Reconciles the day (idempotent rollover) and reloads the today/carried lists.
    public func refresh(now: Date = .now) {
        rollover.performRolloverIfNeeded(now: now)
        todayTodos = (try? store.todos(on: now, calendar: calendar)) ?? []
        carriedTodos = (try? store.overdueIncompleteTodos(before: now, calendar: calendar)) ?? []
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

    private func handlePhaseEnd(_ phase: PomodoroPhase) {
        #if canImport(AppKit)
        if Preferences.soundEnabled { AppKitBridge.playPhaseEndSound(named: Preferences.soundName) }
        #endif
    }
}
