import XCTest
@testable import DayBarCore

@MainActor
final class HabitEngineTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testMaterializesTodayForActiveTemplate() throws {
        let store = DataStore(inMemory: true)
        let template = HabitTemplate(title: "Read", createdDate: now)
        store.insert(template)
        store.save()

        let engine = HabitEngine(store: store, calendar: cal)
        XCTAssertTrue(engine.materializeIfNeeded(now: now))

        let today = cal.startOfDay(for: now)
        let logs = try store.habitLogs(on: now, calendar: cal)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.templateId, template.id)
        XCTAssertEqual(logs.first?.day, today)
        XCTAssertEqual(logs.first?.status, .pending)
    }

    func testMaterializeIsIdempotentSameDay() throws {
        let store = DataStore(inMemory: true)
        store.insert(HabitTemplate(title: "Water", createdDate: now))
        store.save()

        let engine = HabitEngine(store: store, calendar: cal)
        XCTAssertTrue(engine.materializeIfNeeded(now: now))
        XCTAssertFalse(engine.materializeIfNeeded(now: now))

        XCTAssertEqual(try store.habitLogs(on: now, calendar: cal).count, 1)
    }

    func testNewTemplateMidDayGetsTodayLog() throws {
        let store = DataStore(inMemory: true)
        let engine = HabitEngine(store: store, calendar: cal)
        engine.materializeIfNeeded(now: now)

        store.insert(HabitTemplate(title: "Late add", createdDate: now))
        store.save()
        XCTAssertTrue(engine.materializeIfNeeded(now: now))

        XCTAssertEqual(try store.habitLogs(on: now, calendar: cal).count, 1)
    }

    func testArchivedTemplateStopsNewLogs() throws {
        let store = DataStore(inMemory: true)
        let template = HabitTemplate(title: "Old", isActive: false)
        store.insert(template)
        store.save()

        let engine = HabitEngine(store: store, calendar: cal)
        engine.materializeIfNeeded(now: now)

        XCTAssertEqual(try store.habitLogs(on: now, calendar: cal).count, 0)
    }

    func testCatchUpAcrossMultipleDays() throws {
        let store = DataStore(inMemory: true)
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: now))!
        let template = HabitTemplate(title: "Daily", createdDate: twoDaysAgo)
        store.insert(template)
        let meta = try store.appMeta()
        meta.lastHabitMaterializedDay = twoDaysAgo
        store.save()

        let engine = HabitEngine(store: store, calendar: cal)
        XCTAssertTrue(engine.materializeIfNeeded(now: now))

        let all = try store.allHabitLogs()
        XCTAssertEqual(all.count, 2) // yesterday + today (not before template existed if same)
    }
}