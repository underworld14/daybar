import XCTest
@testable import DayBarCore

@MainActor
final class AppStateHabitTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeAppStateWithHabit(title: String) -> (AppState, HabitTemplate) {
        let store = DataStore(inMemory: true)
        let template = HabitTemplate(title: title, createdDate: now)
        store.insert(template)
        store.save()
        let appState = AppState(store: store, calendar: cal)
        return (appState, template)
    }

    func testToggleHabitMarksCompletedAndUpdatesStreak() throws {
        let (appState, template) = makeAppStateWithHabit(title: "Read")
        guard let log = appState.todayHabits.first(where: { $0.template.id == template.id })?.log else {
            XCTFail("expected today log")
            return
        }

        appState.toggleHabit(log, now: now)

        XCTAssertEqual(log.status, .completed)
        XCTAssertEqual(appState.todayHabits.first?.currentStreak, 1)
    }

    func testSkipHabitMarksSkipped() throws {
        let (appState, template) = makeAppStateWithHabit(title: "Walk")
        guard let log = appState.todayHabits.first(where: { $0.template.id == template.id })?.log else {
            XCTFail("expected today log")
            return
        }

        appState.skipHabit(log, now: now)

        XCTAssertEqual(log.status, .skipped)
        XCTAssertEqual(appState.completedHabitsTodayCount, 0)
    }

    func testHabitStreakEntriesCachedAfterRefresh() throws {
        let (appState, _) = makeAppStateWithHabit(title: "Meditate")

        XCTAssertEqual(appState.habitStreakEntries.count, 1)
        XCTAssertEqual(appState.habitStreakEntries.first?.heatmap.count, 28)
    }
}