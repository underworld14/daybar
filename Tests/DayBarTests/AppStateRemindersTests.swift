import XCTest
@testable import DayBarCore

@MainActor
final class AppStateRemindersTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: PreferenceKeys.remindersSyncEnabled)
        UserDefaults.standard.set(false, forKey: PreferenceKeys.remindersHabitsSyncEnabled)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.remindersSyncEnabled)
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.remindersHabitsSyncEnabled)
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.selectedReminderCalendarIDs)
        super.tearDown()
    }

    func testHydratesRemindersLastSyncedAtFromMeta() throws {
        let store = DataStore(inMemory: true)
        let meta = try store.appMeta()
        meta.remindersLastSyncedAt = now
        store.save()

        let appState = AppState(store: store, calendar: cal, remindersProvider: MockRemindersProvider())
        XCTAssertEqual(appState.remindersLastSyncedAt, now)
    }

    func testCoalescesOverlappingSyncRequests() async throws {
        UserDefaults.standard.set(true, forKey: PreferenceKeys.remindersSyncEnabled)
        UserDefaults.standard.set(["list-1"], forKey: PreferenceKeys.selectedReminderCalendarIDs)

        let store = DataStore(inMemory: true)
        let mock = MockRemindersProvider()
        mock.fetchIncompleteDelayNanoseconds = 50_000_000
        let appState = AppState(store: store, calendar: cal, remindersProvider: mock)

        appState.invalidateRemindersSync()
        appState.refresh(now: now)
        XCTAssertTrue(appState.isRemindersSyncing)

        appState.invalidateRemindersSync()
        appState.refresh(now: now)

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(appState.isRemindersSyncing)
        XCTAssertNotNil(appState.remindersLastSyncedAt)
    }
}