import XCTest
@testable import DayBarCore

/// Habit behavior covered at the store/analytics layer; AppState wiring for habits is exercised
/// via `HabitRemindersSyncEngineTests` and `HabitEngineTests` to avoid EventKit run-loop coupling.
@MainActor
final class AppStateHabitTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    }

    func testToggleMarksCompletedAndUpdatesStreak() throws {
        let store = DataStore(inMemory: true)
        let template = HabitTemplate(title: "Read", createdDate: now)
        store.insert(template)
        store.save()
        HabitEngine(store: store, calendar: cal).materializeIfNeeded(now: now)

        let log = try XCTUnwrap(try store.habitLogs(on: now, calendar: cal).first)
        log.completedAt = now
        log.status = .completed
        store.save()

        let info = HabitAnalytics.streakInfo(
            logs: try store.allHabitLogs(), template: template, asOf: now, calendar: cal
        )
        XCTAssertEqual(log.status, .completed)
        XCTAssertEqual(info.current, 1)
    }

    func testSkipMarksSkipped() throws {
        let store = DataStore(inMemory: true)
        let template = HabitTemplate(title: "Walk", createdDate: now)
        store.insert(template)
        store.save()
        HabitEngine(store: store, calendar: cal).materializeIfNeeded(now: now)

        let log = try XCTUnwrap(try store.habitLogs(on: now, calendar: cal).first)
        log.status = .skipped
        log.completedAt = nil
        store.save()

        XCTAssertEqual(log.status, .skipped)
    }

    func testHeatmapCachedShape() throws {
        let store = DataStore(inMemory: true)
        let template = HabitTemplate(title: "Meditate", createdDate: now)
        store.insert(template)
        store.save()
        HabitEngine(store: store, calendar: cal).materializeIfNeeded(now: now)

        let heatmap = HabitAnalytics.heatmap(
            logs: try store.allHabitLogs(), template: template, days: 28, endingAt: now, calendar: cal
        )
        XCTAssertEqual(heatmap.count, 28)
    }

    func testArchivedTemplateRetainsAnalyticsHistory() throws {
        let store = DataStore(inMemory: true)
        let template = HabitTemplate(title: "Old ritual", createdDate: now)
        store.insert(template)
        store.save()
        HabitEngine(store: store, calendar: cal).materializeIfNeeded(now: now)

        let log = try XCTUnwrap(try store.habitLogs(on: now, calendar: cal).first)
        log.status = .completed
        log.completedAt = now
        template.isActive = false
        store.save()

        let logs = try store.allHabitLogs()
        let info = HabitAnalytics.streakInfo(logs: logs, template: template, asOf: now, calendar: cal)
        XCTAssertFalse(template.isActive)
        XCTAssertEqual(info.best, 1)
    }
}