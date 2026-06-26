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
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.remindersPushNewTodos)
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
                calendarTitle: "Personal",
                modifiedAt: now
            ),
        ]

        let pulled = await engine.reconcileIfNeeded(now: now, force: true)
        XCTAssertTrue(pulled)

        let todo = try store.todo(externalIdentifier: "ext-1")
        XCTAssertEqual(todo?.title, "From Reminders")
        XCTAssertEqual(todo?.source, .reminders)
        XCTAssertEqual(todo?.externalModifiedAt, now)
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
        existing.externalModifiedAt = today
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

    func testCompleteLocallyDoesNotDeleteMirror() async throws {
        let (store, mock, engine) = makeEngine()
        let todo = DailyTodo(
            title: "Done",
            plannedForDate: today,
            originalPlannedDate: today,
            source: .reminders,
            externalIdentifier: "ext-complete"
        )
        todo.completedDate = now
        todo.status = .completed
        store.insert(todo)
        store.save()

        mock.reminders = [
            ReminderDTO(
                externalIdentifier: "ext-complete",
                title: "Done",
                dueDate: today,
                isCompleted: true,
                completionDate: now,
                calendarIdentifier: "list-1",
                modifiedAt: now
            ),
        ]

        _ = await engine.reconcileIfNeeded(now: now, force: true)

        let kept = try store.todo(externalIdentifier: "ext-complete")
        XCTAssertNotNil(kept)
        XCTAssertTrue(kept?.isCompleted == true)
    }

    func testDelayDoesNotDeleteMirror() async throws {
        let (store, mock, engine) = makeEngine()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let todo = DailyTodo(
            title: "Later",
            plannedForDate: tomorrow,
            originalPlannedDate: today,
            source: .reminders,
            externalIdentifier: "ext-delay"
        )
        todo.status = .snoozed
        store.insert(todo)
        store.save()

        mock.reminders = [
            ReminderDTO(
                externalIdentifier: "ext-delay",
                title: "Later",
                dueDate: tomorrow,
                calendarIdentifier: "list-1",
                modifiedAt: now
            ),
        ]

        _ = await engine.reconcileIfNeeded(now: now, force: true)

        let kept = try store.todo(externalIdentifier: "ext-delay")
        XCTAssertNotNil(kept)
        XCTAssertEqual(kept?.plannedForDate, tomorrow)
    }

    func testRemoteCompleteUpdatesLocalMirror() async throws {
        let (store, mock, engine) = makeEngine()
        store.insert(DailyTodo(
            title: "Remote done",
            plannedForDate: today,
            originalPlannedDate: today,
            source: .reminders,
            externalIdentifier: "ext-remote-done"
        ))
        store.save()

        mock.reminders = [
            ReminderDTO(
                externalIdentifier: "ext-remote-done",
                title: "Remote done",
                dueDate: today,
                isCompleted: true,
                completionDate: now,
                calendarIdentifier: "list-1",
                modifiedAt: now
            ),
        ]

        _ = await engine.reconcileIfNeeded(now: now, force: true)

        let updated = try store.todo(externalIdentifier: "ext-remote-done")
        XCTAssertTrue(updated?.isCompleted == true)
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
        XCTAssertEqual(todo.externalModifiedAt, now)
    }

    func testPushCompleteUpdatesExternalModifiedAt() async throws {
        let (store, mock, engine) = makeEngine()
        let todo = DailyTodo(
            title: "Finish",
            plannedForDate: today,
            originalPlannedDate: today,
            source: .reminders,
            externalIdentifier: "ext-push"
        )
        store.insert(todo)
        mock.reminders = [
            ReminderDTO(
                externalIdentifier: "ext-push",
                title: "Finish",
                dueDate: today,
                calendarIdentifier: "list-1"
            ),
        ]
        store.save()

        todo.completedDate = now
        todo.status = .completed
        engine.enqueuePush(for: todo)
        _ = await engine.reconcileIfNeeded(now: now, force: true)

        XCTAssertEqual(mock.applied.count, 1)
        XCTAssertTrue(mock.applied.first?.isCompleted == true)
        XCTAssertEqual(todo.externalModifiedAt, now)
    }

    func testSkipsRemoteUpdateWhenLocalIsNewer() async throws {
        let (store, mock, engine) = makeEngine()
        let localModified = now.addingTimeInterval(3600)
        let existing = DailyTodo(
            title: "Local wins",
            plannedForDate: today,
            originalPlannedDate: today,
            source: .reminders,
            externalIdentifier: "ext-conflict"
        )
        existing.externalModifiedAt = localModified
        store.insert(existing)
        store.save()

        mock.reminders = [
            ReminderDTO(
                externalIdentifier: "ext-conflict",
                title: "Remote rename",
                dueDate: today,
                calendarIdentifier: "list-1",
                modifiedAt: now
            ),
        ]

        _ = await engine.reconcileIfNeeded(now: now, force: true)
        XCTAssertEqual(try store.todo(externalIdentifier: "ext-conflict")?.title, "Local wins")
    }

    func testCreateReminderForNewTodo() async throws {
        UserDefaults.standard.set(true, forKey: PreferenceKeys.remindersPushNewTodos)
        let (store, mock, engine) = makeEngine()
        let todo = DailyTodo(title: "New local", plannedForDate: today, originalPlannedDate: today)
        store.insert(todo)
        store.save()

        await engine.createReminderForNewTodo(todo, now: now)

        XCTAssertEqual(todo.source, .reminders)
        XCTAssertNotNil(todo.externalIdentifier)
        XCTAssertEqual(mock.created.count, 1)
    }

    func testPullFailureDoesNotUpdateMetaTimestamp() async throws {
        let (store, mock, engine) = makeEngine()
        mock.shouldThrow = true

        let changed = await engine.reconcileIfNeeded(now: now, force: true)
        XCTAssertFalse(changed)

        let meta = try store.appMeta()
        XCTAssertNil(meta.remindersLastSyncedAt)
        XCTAssertNotNil(engine.lastSyncError)
    }

    func testHydratesLastSyncedFromMeta() throws {
        let store = DataStore(inMemory: true)
        let meta = try store.appMeta()
        meta.remindersLastSyncedAt = now
        store.save()

        let engine = RemindersSyncEngine(store: store, provider: MockRemindersProvider(), calendar: cal)
        XCTAssertEqual(engine.lastSyncedAt, now)
    }

    func testPushFailureSurvivesSuccessfulPull() async throws {
        let (store, mock, engine) = makeEngine()
        let todo = DailyTodo(
            title: "Push fail",
            plannedForDate: today,
            originalPlannedDate: today,
            source: .reminders,
            externalIdentifier: "ext-push-fail"
        )
        store.insert(todo)
        store.save()
        mock.reminders = [
            ReminderDTO(
                externalIdentifier: "ext-other",
                title: "Other",
                dueDate: today,
                calendarIdentifier: "list-1"
            ),
        ]
        mock.failApplyIdentifiers = ["ext-push-fail"]

        todo.completedDate = now
        todo.status = .completed
        engine.enqueuePush(for: todo)
        _ = await engine.reconcileIfNeeded(now: now, force: true)

        XCTAssertNotNil(engine.lastSyncError)
        XCTAssertNil(try store.appMeta().remindersLastSyncedAt)
    }

    func testReconcileFailureDoesNotUpdateMeta() async throws {
        let (store, mock, engine) = makeEngine()
        store.insert(DailyTodo(
            title: "Bad reconcile",
            plannedForDate: today,
            originalPlannedDate: today,
            source: .reminders,
            externalIdentifier: "ext-bad-reconcile"
        ))
        store.save()
        mock.reminders = [
            ReminderDTO(
                externalIdentifier: "ext-bad-reconcile",
                title: "Bad reconcile",
                dueDate: today,
                isCompleted: true,
                completionDate: now,
                calendarIdentifier: "list-1"
            ),
        ]
        mock.fetchReminderThrowIdentifiers = ["ext-bad-reconcile"]

        _ = await engine.reconcileIfNeeded(now: now, force: true)

        XCTAssertNotNil(engine.lastSyncError)
        XCTAssertNil(try store.appMeta().remindersLastSyncedAt)
    }

    func testSkipsWhenSyncDisabled() async {
        UserDefaults.standard.set(false, forKey: PreferenceKeys.remindersSyncEnabled)
        let (_, _, engine) = makeEngine()
        let skipped = await engine.reconcileIfNeeded(now: now, force: true)
        XCTAssertFalse(skipped)
    }
}