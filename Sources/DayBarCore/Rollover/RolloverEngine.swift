import Foundation

/// Idempotent new-day rollover. Marks every past-due, incomplete todo as `carriedOver`
/// and records `lastProcessedDay` in the same save. Keyed on the persisted day, so it is
/// safe to call redundantly from all four triggers (launch, become-active, wake,
/// calendar-day-change) and survives the Mac sleeping across one or many days.
@MainActor
public final class RolloverEngine {
    private let store: DataStore
    public var calendar: Calendar

    public init(store: DataStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    /// Runs the rollover only if the calendar day has advanced since `lastProcessedDay`.
    /// Returns true when it actually processed a new day.
    @discardableResult
    public func performRolloverIfNeeded(now: Date = .now) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let meta = try? store.appMeta() else { return false }

        if let last = meta.lastProcessedDay, calendar.startOfDay(for: last) >= today {
            return false // already processed today — idempotent
        }

        let backlog = (try? store.overdueIncompleteTodos(before: today, calendar: calendar)) ?? []
        for todo in backlog where todo.status != .carriedOver {
            todo.status = .carriedOver
        }

        meta.lastProcessedDay = today
        return store.save()
    }
}
