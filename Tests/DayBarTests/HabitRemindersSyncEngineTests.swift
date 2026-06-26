import XCTest
@testable import DayBarCore

@MainActor
final class HabitRemindersSyncEngineTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: PreferenceKeys.remindersHabitsSyncEnabled)
        UserDefaults.standard.set(["list-1"], forKey: PreferenceKeys.selectedHabitReminderCalendarIDs)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.remindersHabitsSyncEnabled)
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.selectedHabitReminderCalendarIDs)
        super.tearDown()
    }

    private func makeEngine() -> (DataStore, MockRemindersProvider, HabitRemindersSyncEngine) {
        let store = DataStore(inMemory: true)
        let mock = MockRemindersProvider()
        let engine = HabitRemindersSyncEngine(store: store, provider: mock, calendar: cal)
        return (store, mock, engine)
    }

    func testPushCreatesReminderForNewSyncedHabit() async throws {
        let (store, mock, engine) = makeEngine()
        let template = HabitTemplate(title: "Meditate", remindersSyncEnabled: true)
        store.insert(template)
        store.insert(HabitLog(templateId: template.id, day: cal.startOfDay(for: now)))
        store.save()

        engine.enqueuePush(for: template)
        let changed = await engine.reconcileIfNeeded(now: now, force: true)

        XCTAssertTrue(changed)
        XCTAssertEqual(mock.createdHabits.count, 1)
        XCTAssertNotNil(template.externalReminderIdentifier)
    }

    func testPullCompletesLocalLog() async throws {
        let (store, mock, engine) = makeEngine()
        let template = HabitTemplate(
            title: "Stretch",
            remindersSyncEnabled: true,
            externalReminderIdentifier: "habit-1",
            remindersCalendarIdentifier: "list-1"
        )
        store.insert(template)
        let log = HabitLog(templateId: template.id, day: cal.startOfDay(for: now), status: .pending)
        store.insert(log)
        store.save()

        mock.habitReminders = [
            HabitReminderDTO(
                externalIdentifier: "habit-1",
                templateId: template.id,
                title: "Stretch",
                notes: HabitReminderMapping.buildNotes(templateId: template.id, cueText: ""),
                isCompleted: true,
                completionDate: now,
                calendarIdentifier: "list-1",
                modifiedAt: now
            ),
        ]

        _ = await engine.reconcileIfNeeded(now: now, force: true)
        XCTAssertTrue(log.isCompleted)
    }

    func testDisabledPreferenceNoOps() async {
        UserDefaults.standard.set(false, forKey: PreferenceKeys.remindersHabitsSyncEnabled)
        let (store, _, engine) = makeEngine()
        let template = HabitTemplate(title: "No sync", remindersSyncEnabled: true)
        store.insert(template)
        store.save()
        engine.enqueuePush(for: template)
        let changed = await engine.reconcileIfNeeded(now: now, force: true)
        XCTAssertFalse(changed)
    }
}