import Foundation
import DayBarCore

/// Lightweight headless verification of the DayBar core logic. Command Line Tools ships
/// no XCTest/Testing module, so this executable runs the assertions directly and exits
/// non-zero on any failure. Run with `swift run DayBarChecks`.
@main
struct Checks {
    @MainActor
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if condition {
                print("  ✓ \(message)")
            } else {
                print("  ✗ \(message)")
                failures += 1
            }
        }

        print("EscalationModel")
        check(EscalationModel.tier(forAgeInDays: 0) == .onPlan, "age 0 → onPlan")
        check(EscalationModel.tier(forAgeInDays: 1) == .slipped, "age 1 → slipped")
        check(EscalationModel.tier(forAgeInDays: 2) == .slipped, "age 2 → slipped")
        check(EscalationModel.tier(forAgeInDays: 3) == .aging, "age 3 → aging")
        check(EscalationModel.countsTowardBadge(.slipped) == false, "slipped not badged")
        check(EscalationModel.countsTowardBadge(.aging) == true, "aging badged")
        check(EscalationModel.ageLabel(forAgeInDays: 0) == nil, "age 0 → no label")
        check(EscalationModel.ageLabel(forAgeInDays: 3) == "3d", "age 3 → \"3d\"")

        print("DayMath (DST / timezone safe)")
        let ny = calendar("America/New_York")
        let before = ny.date(from: DateComponents(year: 2025, month: 3, day: 8, hour: 12))!
        let after = ny.date(from: DateComponents(year: 2025, month: 3, day: 10, hour: 12))!
        check(DayMath.dayDifference(from: before, to: after, calendar: ny) == 2, "DST spring-forward → 2 days")
        let utc = calendar("UTC")
        let tokyo = calendar("Asia/Tokyo")
        let ref = utc.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 0))!
        let lateUTC = utc.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 23, minute: 30))!
        check(DayMath.dayDifference(from: ref, to: lateUTC, calendar: utc) == 0, "UTC same day → 0")
        check(DayMath.dayDifference(from: ref, to: lateUTC, calendar: tokyo) == 1, "Tokyo crosses midnight → 1")

        let cal = Calendar.current
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))! }

        print("RolloverEngine (idempotent, sleep-safe)")
        do {
            let store = DataStore(inMemory: true)
            let todo = DailyTodo(title: "x", plannedForDate: day(-1), originalPlannedDate: day(-1))
            store.insert(todo); store.save()
            let engine = RolloverEngine(store: store, calendar: cal)
            check(engine.performRolloverIfNeeded(now: now) == true, "runs on a new day")
            check(todo.status == .carriedOver, "past-due incomplete → carriedOver")
            check(engine.performRolloverIfNeeded(now: now) == false, "second call same day is a no-op")
        }
        do {
            let store = DataStore(inMemory: true)
            let done = DailyTodo(title: "done", plannedForDate: day(-1), originalPlannedDate: day(-1),
                                 completedDate: day(-1), status: .completed)
            store.insert(done); store.save()
            _ = RolloverEngine(store: store, calendar: cal).performRolloverIfNeeded(now: now)
            check(done.status == .completed, "completed task is never carried over")
        }
        do {
            let store = DataStore(inMemory: true)
            let todo = DailyTodo(title: "old", plannedForDate: day(-3), originalPlannedDate: day(-3))
            store.insert(todo)
            if let meta = try? store.appMeta() { meta.lastProcessedDay = day(-3) } // 3 days asleep
            store.save()
            _ = RolloverEngine(store: store, calendar: cal).performRolloverIfNeeded(now: now)
            check(todo.status == .carriedOver, "multi-day gap catches up")
            check(todo.carryOverAgeInDays(asOf: now, calendar: cal) == 3, "age escalates to 3")
            check(todo.escalationTier(asOf: now, calendar: cal) == .aging, "tier aging at 3 days")
        }

        print("AppState intents")
        do {
            let app = AppState(store: DataStore(inMemory: true))
            app.addTodo(title: "Write report")
            app.addTodo(title: "   ") // whitespace-only is ignored
            check(app.totalTodayCount == 1, "addTodo adds one (blank ignored)")
            if let t = app.todayTodos.first {
                app.toggleComplete(t)
                check(app.completedTodayCount == 1, "toggleComplete marks done")
                app.toggleComplete(t)
                check(app.completedTodayCount == 0, "toggle again un-completes")
                app.drop(t)
                check(app.totalTodayCount == 0, "drop removes from today")
            }
        }

        print("PomodoroEngine (wall-clock truth, sleep catch-up)")
        do {
            let engine = PomodoroEngine(config: PomodoroConfig(workDuration: 60))
            let t0 = Date(timeIntervalSince1970: 2_000_000_000)
            engine.start(.work, now: t0)
            check(engine.isRunning, "running after start")
            engine.tick(now: t0.addingTimeInterval(30))
            check(Int(engine.remaining.rounded()) == 30, "remaining recomputed from endDate (30s)")
            var ended = false
            engine.onPhaseEnd = { _ in ended = true }
            engine.tick(now: t0.addingTimeInterval(120)) // woke up well past the end
            check(ended, "missed phase-end fires on wake")
            check(engine.completedWorkCount == 1, "completed work session counted")
        }

        if failures == 0 {
            print("\nALL CHECKS PASSED")
        } else {
            print("\n\(failures) CHECK(S) FAILED")
            exit(1)
        }
    }

    private static func calendar(_ tz: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }
}
