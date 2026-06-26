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
        let model = DailyTodo(title: "x", plannedForDate: now, originalPlannedDate: now, status: .carriedOver)
        let template = HabitTemplate(title: "Read")
        let habitLog = HabitLog(templateId: template.id, day: now, status: .completed)
        let snapshot = StoreSnapshotDTO(
            todos: [TodoDTO(model)],
            meta: MetaDTO(lastProcessedDay: now, lastHabitMaterializedDay: now),
            habitTemplates: [HabitTemplateDTO(template)],
            habitLogs: [HabitLogDTO(habitLog)]
        )
        let data = try JSONStore.encode(snapshot)
        let decoded = try JSONStore.decode(data)
        XCTAssertEqual(decoded.todos.count, 1)
        XCTAssertEqual(decoded.todos.first?.statusRaw, TodoStatus.carriedOver.rawValue)
        XCTAssertEqual(decoded.meta?.lastProcessedDay, now)
        XCTAssertEqual(decoded.habitTemplates.count, 1)
        XCTAssertEqual(decoded.habitLogs.count, 1)
    }

    func testLegacyJSONWithoutHabitsDecodes() throws {
        let model = DailyTodo(title: "x", plannedForDate: now, originalPlannedDate: now)
        let snapshot = StoreSnapshotDTO(todos: [TodoDTO(model)], meta: MetaDTO(lastProcessedDay: now))
        let data = try JSONStore.encode(snapshot)
        let decoded = try JSONStore.decode(data)
        XCTAssertTrue(decoded.habitTemplates.isEmpty)
        XCTAssertTrue(decoded.habitLogs.isEmpty)
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
}
