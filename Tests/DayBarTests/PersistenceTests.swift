import XCTest
import SwiftData
@testable import DayBarCore

@MainActor
final class PersistenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testInsertAndQueryToday() throws {
        let store = DataStore(inMemory: true)
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        store.insert(DailyTodo(title: "a", plannedForDate: today, originalPlannedDate: today))
        store.save()

        let todays = try store.todos(on: now)
        XCTAssertEqual(todays.count, 1)
        XCTAssertEqual(todays.first?.title, "a")
    }

    func testOverdueQueryExcludesDropped() throws {
        let store = DataStore(inMemory: true)
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!
        store.insert(DailyTodo(title: "keep", plannedForDate: yesterday, originalPlannedDate: yesterday))
        store.insert(DailyTodo(title: "gone", plannedForDate: yesterday, originalPlannedDate: yesterday, status: .dropped))
        store.save()

        let overdue = try store.overdueIncompleteTodos(before: now)
        XCTAssertEqual(overdue.map(\.title), ["keep"])
    }

    func testJSONRoundTrip() throws {
        let modified = Date(timeIntervalSince1970: 1_700_000_100)
        let model = DailyTodo(
            title: "x",
            plannedForDate: now,
            originalPlannedDate: now,
            status: .carriedOver,
            source: .reminders,
            externalIdentifier: "ext-json"
        )
        model.externalModifiedAt = modified
        let template = HabitTemplate(title: "Read")
        let habitLog = HabitLog(templateId: template.id, day: now, status: .completed)
        let session = FocusSession(id: UUID(), endedAt: now, minutes: 25, completed: true)
        model.notes = "detail notes"
        let checklist = ChecklistItemDTO(
            id: UUID(), todoId: model.id, title: "Step one", isCompleted: true, sortOrder: 0
        )
        let snapshot = StoreSnapshotDTO(
            todos: [TodoDTO(model)],
            meta: MetaDTO(lastProcessedDay: now, lastHabitMaterializedDay: now),
            habitTemplates: [HabitTemplateDTO(template)],
            habitLogs: [HabitLogDTO(habitLog)],
            focusSessions: [FocusSessionDTO(session)],
            checklistItems: [checklist]
        )
        let data = try JSONStore.encode(snapshot)
        let decoded = try JSONStore.decode(data)
        XCTAssertEqual(decoded.todos.count, 1)
        XCTAssertEqual(decoded.todos.first?.statusRaw, TodoStatus.carriedOver.rawValue)
        XCTAssertEqual(decoded.todos.first?.externalIdentifier, "ext-json")
        XCTAssertEqual(decoded.todos.first?.externalModifiedAt, modified)
        XCTAssertEqual(decoded.todos.first?.makeModel().externalModifiedAt, modified)
        XCTAssertEqual(decoded.meta?.lastProcessedDay, now)
        XCTAssertEqual(decoded.habitTemplates.count, 1)
        XCTAssertEqual(decoded.habitLogs.count, 1)
        XCTAssertEqual(decoded.focusSessions?.count, 1)
        XCTAssertEqual(decoded.focusSessions?.first?.minutes, 25)
        XCTAssertEqual(decoded.focusSessions?.first?.completed, true)
        XCTAssertEqual(decoded.todos.first?.notes, "detail notes")
        XCTAssertEqual(decoded.checklistItems.count, 1)
        XCTAssertEqual(decoded.checklistItems.first?.title, "Step one")
        XCTAssertEqual(decoded.checklistItems.first?.isCompleted, true)
        XCTAssertEqual(decoded.checklistItems.first?.todoId, model.id)
    }

    func testLegacyJSONWithoutHabitsDecodes() throws {
        let model = DailyTodo(title: "x", plannedForDate: now, originalPlannedDate: now)
        let snapshot = StoreSnapshotDTO(todos: [TodoDTO(model)], meta: MetaDTO(lastProcessedDay: now))
        let data = try JSONStore.encode(snapshot)
        let decoded = try JSONStore.decode(data)
        XCTAssertTrue(decoded.habitTemplates.isEmpty)
        XCTAssertTrue(decoded.habitLogs.isEmpty)
        XCTAssertNil(decoded.focusSessions)
    }

    func testImportSnapshotReplacesFocusSessions() throws {
        let store = DataStore(inMemory: true)
        store.insert(FocusSession(endedAt: now, minutes: 10, completed: false))
        store.save()

        let imported = FocusSessionDTO(
            id: UUID(), endedAt: now, minutes: 25, completed: true
        )
        store.importSnapshot(StoreSnapshotDTO(todos: [], focusSessions: [imported]))

        let sessions = try store.allFocusSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.minutes, 25)
        XCTAssertEqual(sessions.first?.completed, true)
    }

    func testImportLegacySnapshotPreservesFocusSessions() throws {
        let store = DataStore(inMemory: true)
        store.insert(FocusSession(endedAt: now, minutes: 40, completed: true))
        store.save()

        // No focusSessions key — older backup shape.
        store.importSnapshot(StoreSnapshotDTO(todos: [], focusSessions: nil))

        let sessions = try store.allFocusSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.minutes, 40)
    }

    func testImportSnapshotReplacesAll() throws {
        let store = DataStore(inMemory: true)
        store.insert(DailyTodo(title: "old", plannedForDate: now, originalPlannedDate: now))
        store.save()

        let fresh = TodoDTO(DailyTodo(title: "new", plannedForDate: now, originalPlannedDate: now))
        store.importSnapshot(StoreSnapshotDTO(todos: [fresh]))

        let all = try store.allTodos()
        XCTAssertEqual(all.map(\.title), ["new"])
    }

    func testImportSnapshotReplacesHabits() throws {
        let store = DataStore(inMemory: true)
        let oldTemplate = HabitTemplate(title: "Old habit")
        store.insert(oldTemplate)
        store.insert(HabitLog(templateId: oldTemplate.id, day: now, status: .completed))
        store.save()

        let newTemplate = HabitTemplate(title: "Imported habit")
        let newLog = HabitLog(templateId: newTemplate.id, day: now, status: .pending)
        store.importSnapshot(
            StoreSnapshotDTO(
                todos: [],
                habitTemplates: [HabitTemplateDTO(newTemplate)],
                habitLogs: [HabitLogDTO(newLog)]
            )
        )

        XCTAssertEqual(try store.allHabitTemplates().map(\.title), ["Imported habit"])
        XCTAssertEqual(try store.allHabitLogs().count, 1)
        XCTAssertEqual(try store.allHabitLogs().first?.status, .pending)
    }

    func testImportSnapshotWithOverlappingIDs() throws {
        let store = DataStore(inMemory: true)
        let shared = UUID()
        store.insert(DailyTodo(id: shared, title: "before", plannedForDate: now, originalPlannedDate: now))
        store.save()

        let dto = TodoDTO(DailyTodo(id: shared, title: "after", plannedForDate: now, originalPlannedDate: now))
        store.importSnapshot(StoreSnapshotDTO(todos: [dto]))

        let all = try store.allTodos()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "after")
    }

    func testTodayQuerySortsByPriority() throws {
        let store = DataStore(inMemory: true)
        let today = Calendar.current.startOfDay(for: now)
        store.insert(DailyTodo(title: "low", plannedForDate: today, originalPlannedDate: today, priority: .low))
        store.insert(DailyTodo(title: "high", plannedForDate: today, originalPlannedDate: today, priority: .high))
        store.save()
        XCTAssertEqual(try store.todos(on: now).map(\.title), ["high", "low"])
    }

    // MARK: - Legacy import (the irreversible Phase-1 → SwiftData migration)

    func testLegacyImportRunsOnceThenIsIdempotent() throws {
        let store = DataStore(inMemory: true)
        let snapshot = StoreSnapshotDTO(
            todos: [TodoDTO(DailyTodo(title: "legacy", plannedForDate: now, originalPlannedDate: now))],
            meta: MetaDTO(lastProcessedDay: now)
        )
        store.performLegacyImport(snapshot: snapshot, legacyFileExists: true)
        XCTAssertEqual(try store.allTodos().map(\.title), ["legacy"])
        XCTAssertTrue(try store.appMeta().didImportLegacyJSON)
        XCTAssertEqual(try store.appMeta().lastProcessedDay, now)

        store.performLegacyImport(snapshot: snapshot, legacyFileExists: true)
        XCTAssertEqual(try store.allTodos().count, 1, "must not double-import")
    }

    func testLegacyImportSkippedWhenStoreHasData() throws {
        let store = DataStore(inMemory: true)
        store.insert(DailyTodo(title: "existing", plannedForDate: now, originalPlannedDate: now))
        store.save()
        let snapshot = StoreSnapshotDTO(todos: [TodoDTO(DailyTodo(title: "legacy", plannedForDate: now, originalPlannedDate: now))])
        store.performLegacyImport(snapshot: snapshot, legacyFileExists: true)
        XCTAssertEqual(try store.allTodos().map(\.title), ["existing"])
        XCTAssertTrue(try store.appMeta().didImportLegacyJSON)
    }

    func testLegacyImportRetriesWhenFileUnreadable() throws {
        let store = DataStore(inMemory: true)
        store.performLegacyImport(snapshot: nil, legacyFileExists: true)
        XCTAssertFalse(try store.appMeta().didImportLegacyJSON, "guard must stay unset so we retry")
        XCTAssertEqual(try store.allTodos().count, 0)
    }

    func testLegacyImportMarksDoneWhenNoFile() throws {
        let store = DataStore(inMemory: true)
        store.performLegacyImport(snapshot: nil, legacyFileExists: false)
        XCTAssertTrue(try store.appMeta().didImportLegacyJSON)
        XCTAssertEqual(try store.allTodos().count, 0)
    }

    func testStoreURLIsUnderDayBar() {
        let path = PersistencePaths.storeURL.path
        XCTAssertTrue(path.hasSuffix("DayBar/daybar.store"), path)
    }

    func testMigrateDefaultStoreWhenDestinationMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("daybar-migrate-\(UUID().uuidString)", isDirectory: true)
        let dayBar = root.appendingPathComponent("DayBar", isDirectory: true)
        let source = root.appendingPathComponent("default.store")
        let dest = dayBar.appendingPathComponent("daybar.store")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("store".utf8).write(to: source)
        try Data("shm".utf8).write(to: URL(fileURLWithPath: source.path + "-shm"))

        XCTAssertTrue(PersistencePaths.migrateDefaultStoreIfNeeded(
            applicationSupport: root, dayBarDirectory: dayBar
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), "store")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path + "-shm"))

        // Destination already present with no orphan sidecars → no-op.
        try Data("other".utf8).write(to: root.appendingPathComponent("default.store"))
        XCTAssertFalse(PersistencePaths.migrateDefaultStoreIfNeeded(
            applicationSupport: root, dayBarDirectory: dayBar
        ))
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), "store")
    }

    func testMigrateHealsOrphanedSidecarsWhenDestinationExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("daybar-heal-\(UUID().uuidString)", isDirectory: true)
        let dayBar = root.appendingPathComponent("DayBar", isDirectory: true)
        let source = root.appendingPathComponent("default.store")
        let dest = dayBar.appendingPathComponent("daybar.store")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: dayBar, withIntermediateDirectories: true)
        try Data("store".utf8).write(to: dest)
        // Simulate partial migrate: main moved, wal left behind.
        try Data("wal".utf8).write(to: URL(fileURLWithPath: source.path + "-wal"))

        XCTAssertTrue(PersistencePaths.migrateDefaultStoreIfNeeded(
            applicationSupport: root, dayBarDirectory: dayBar
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path + "-wal"))
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: dest.path + "-wal"), encoding: .utf8),
            "wal"
        )
    }

    func testLegacyNeutralizeSkippedWhenSaveWouldLoseRetry() throws {
        // Unreadable legacy leaves guard unset and must not neutralize (retry next launch).
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("daybar-noretry-\(UUID().uuidString)", isDirectory: true)
        let legacy = root.appendingPathComponent("daybar-store.json")
        let imported = root.appendingPathComponent("daybar-store.json.imported")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: legacy)

        let store = DataStore(inMemory: true)
        var neutralized = false
        store.performLegacyImport(
            snapshot: nil,
            legacyFileExists: true,
            neutralizeLegacyFile: {
                neutralized = PersistencePaths.neutralizeLegacyFileIfPresent(
                    legacyURL: legacy, importedURL: imported
                )
            }
        )
        XCTAssertFalse(neutralized)
        XCTAssertFalse(try store.appMeta().didImportLegacyJSON)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testLegacyFileRenamedAfterSuccessfulImport() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("daybar-legacy-\(UUID().uuidString)", isDirectory: true)
        let legacy = root.appendingPathComponent("daybar-store.json")
        let imported = root.appendingPathComponent("daybar-store.json.imported")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let snapshot = StoreSnapshotDTO(
            todos: [TodoDTO(DailyTodo(title: "Halo", plannedForDate: now, originalPlannedDate: now))]
        )
        try JSONStore.encode(snapshot).write(to: legacy)

        let store = DataStore(inMemory: true)
        var neutralized = false
        store.performLegacyImport(
            snapshot: snapshot,
            legacyFileExists: true,
            neutralizeLegacyFile: {
                neutralized = PersistencePaths.neutralizeLegacyFileIfPresent(
                    legacyURL: legacy, importedURL: imported
                )
            }
        )
        XCTAssertTrue(neutralized)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.path))

        // Empty store + neutralized legacy path → no re-import.
        let empty = DataStore(inMemory: true)
        empty.performLegacyImport(
            snapshot: JSONStore.loadLegacy(from: legacy),
            legacyFileExists: FileManager.default.fileExists(atPath: legacy.path)
        )
        XCTAssertEqual(try empty.allTodos().count, 0)
        XCTAssertTrue(try empty.appMeta().didImportLegacyJSON)
    }

    func testLegacyJSONWithoutChecklistDecodesEmpty() throws {
        let model = DailyTodo(title: "x", plannedForDate: now, originalPlannedDate: now)
        let snapshot = StoreSnapshotDTO(todos: [TodoDTO(model)], meta: MetaDTO(lastProcessedDay: now))
        let data = try JSONStore.encode(snapshot)
        // Strip checklistItems key to simulate older backup shape.
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "checklistItems")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONStore.decode(stripped)
        XCTAssertTrue(decoded.checklistItems.isEmpty)
    }

    func testImportSnapshotRoundTripsChecklist() throws {
        let store = DataStore(inMemory: true)
        let todo = DailyTodo(title: "with list", notes: "body", plannedForDate: now, originalPlannedDate: now)
        let item = TodoChecklistItem(todoId: todo.id, title: "A", isCompleted: false, sortOrder: 0)
        store.importSnapshot(
            StoreSnapshotDTO(
                todos: [TodoDTO(todo)],
                checklistItems: [ChecklistItemDTO(item)]
            )
        )
        XCTAssertEqual(try store.allTodos().first?.notes, "body")
        let items = try store.allChecklistItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "A")
        XCTAssertEqual(items.first?.todoId, todo.id)

        // Replace clears previous checklist.
        store.importSnapshot(StoreSnapshotDTO(todos: []))
        XCTAssertEqual(try store.allChecklistItems().count, 0)
    }

    func testFocusSessionQuery() throws {
        let store = DataStore(inMemory: true)
        store.insert(FocusSession(endedAt: now, minutes: 25))
        store.save()
        let range = now.addingTimeInterval(-3600)..<now.addingTimeInterval(3600)
        XCTAssertEqual(try store.focusSessions(in: range).count, 1)
        XCTAssertEqual(try store.focusSessions(in: range).first?.minutes, 25)
    }

    func testDayLogUpsertKeepsSingleRow() throws {
        let store = DataStore(inMemory: true)
        let day = Calendar.current.startOfDay(for: now)
        XCTAssertFalse(store.hasDayLog(on: day))
        store.upsertDayLog(day: day, reflection: "good", plannedCount: 3, completedCount: 2)
        XCTAssertTrue(store.hasDayLog(on: day))
        store.upsertDayLog(day: day, reflection: "better", plannedCount: 3, completedCount: 3)
        let log = try store.dayLog(for: day)
        XCTAssertEqual(log?.reflection, "better")
        XCTAssertEqual(log?.completedCount, 3)
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<DayLog>()).count, 1)
    }

    func testDayLogUpsertRoundTripsMood() throws {
        let store = DataStore(inMemory: true)
        let day = Calendar.current.startOfDay(for: now)
        store.upsertDayLog(
            day: day, reflection: "productive day", plannedCount: 3, completedCount: 3,
            moodTag: .productive, moodSource: .ai
        )
        let log = try store.dayLog(for: day)
        XCTAssertEqual(log?.moodTag, .productive)
        XCTAssertEqual(log?.moodScore, 1)
        XCTAssertEqual(log?.moodSource, .ai)

        // A later upsert (e.g. user corrects the mood) overwrites in place.
        store.upsertDayLog(
            day: day, reflection: "productive day", plannedCount: 3, completedCount: 3,
            moodTag: .tired, moodSource: .manual
        )
        let updated = try store.dayLog(for: day)
        XCTAssertEqual(updated?.moodTag, .tired)
        XCTAssertEqual(updated?.moodSource, .manual)
        XCTAssertEqual(try store.context.fetch(FetchDescriptor<DayLog>()).count, 1)
    }

    func testDayLogsInRangeQuery() throws {
        let store = DataStore(inMemory: true)
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let lastWeek = cal.date(byAdding: .day, value: -8, to: today)!
        store.upsertDayLog(day: today, reflection: "a", plannedCount: 1, completedCount: 1, moodTag: .happy, moodSource: .manual)
        store.upsertDayLog(day: yesterday, reflection: "b", plannedCount: 1, completedCount: 0, moodTag: .tired, moodSource: .manual)
        store.upsertDayLog(day: lastWeek, reflection: "c", plannedCount: 1, completedCount: 1, moodTag: .proud, moodSource: .manual)

        let start = cal.date(byAdding: .day, value: -7, to: today)!
        let logs = try store.dayLogs(in: start..<cal.date(byAdding: .day, value: 1, to: today)!)
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(Set(logs.map(\.moodTag)), [.happy, .tired])
    }
}
