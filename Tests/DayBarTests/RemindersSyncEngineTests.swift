import XCTest
@testable import DayBarCore

@MainActor
final class RemindersSyncEngineTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let today = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))

    private func makeEngine() -> (DataStore, MockRemindersProvider, RemindersSyncEngine) {
        let store = DataStore(inMemory: true)
        let mock = MockRemindersProvider()
        let engine = RemindersSyncEngine(store: store, provider: mock, calendar: cal)
        return (store, mock, engine)
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: PreferenceKeys.remindersSyncEnabled)
        UserDefaults.standard.set(["list-1"], forKey: PreferenceKeys.selectedReminderCalendarIDs)
        UserDefaults.standard.set(true, forKey: PreferenceKeys.remindersIncludeUndated)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.remindersSyncEnabled)
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.selectedReminderCalendarIDs)
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.remindersIncludeUndated)
        super.tearDown()
    }

    func testPullCreatesMirrorTodo() async throws {
        let (store, mock, engine) = makeEngine()
        mock.reminders = [
            ReminderDTO(
                externalIdentifier: "ext-1",
                title: "From Reminders",
                dueDate: today,
                calendarIdentifier: "list-1",
                calendarTitle: "Personal"
            ),
        ]

        let pulled = await engine.reconcileIfNeeded(now: now, force: true)
        XCTAssertTrue(pulled)

        let todo = try store.todo(externalIdentifier: "ext-1")
        XCTAssertEqual(todo?.title, "From Reminders")
        XCTAssertEqual(todo?.source, .reminders)
    }

    func testPullUpdatesExistingMirror() async throws {
        let (store, mock, engine) = makeEngine()
        let existing = DailyTodo(
            title: "Old",
            plannedForDate: today,
            originalPlannedDate: today,
            source: .reminders,
            externalIdentifier: "ext-2"
        )
        store.insert(existing)
        store.save()

        mock.reminders = [
            ReminderDTO(
                externalIdentifier: "ext-2",
                title: "Renamed",
                dueDate: today,
                calendarIdentifier: "list-1",
                modifiedAt: now
            ),
        ]

        _ = await engine.reconcileIfNeeded(now: now, force: true)
        XCTAssertEqual(try store.todo(externalIdentifier: "ext-2")?.title, "Renamed")
    }

    func testPrunesDeletedRemoteReminders() async throws {
        let (store, mock, engine) = makeEngine()
        store.insert(DailyTodo(
            title: "Gone",
            plannedForDate: today,
            originalPlannedDate: today,
            source: .reminders,
            externalIdentifier: "ext-3"
        ))
        store.save()
        mock.reminders = []

        _ = await engine.reconcileIfNeeded(now: now, force: true)
        XCTAssertNil(try store.todo(externalIdentifier: "ext-3"))
    }

    func testPushQueueMarksCompleteOnDrop() async throws {
        let (store, mock, engine) = makeEngine()
        let todo = DailyTodo(
            title: "Synced",
            plannedForDate: today,
            originalPlannedDate: today,
            source: .reminders,
            externalIdentifier: "ext-4"
        )
        store.insert(todo)
        mock.reminders = [
            ReminderDTO(
                externalIdentifier: "ext-4",
                title: "Synced",
                dueDate: today,
                calendarIdentifier: "list-1"
            ),
        ]
        store.save()

        todo.status = .dropped
        engine.enqueuePush(for: todo)
        _ = await engine.reconcileIfNeeded(now: now, force: true)

        XCTAssertEqual(mock.applied.count, 1)
        XCTAssertTrue(mock.applied.first?.isCompleted == true)
    }

    func testSkipsWhenSyncDisabled() async {
        UserDefaults.standard.set(false, forKey: PreferenceKeys.remindersSyncEnabled)
        let (_, _, engine) = makeEngine()
        let skipped = await engine.reconcileIfNeeded(now: now, force: true)
        XCTAssertFalse(skipped)
    }
}