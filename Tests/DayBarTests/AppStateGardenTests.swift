import XCTest
@testable import DayBarCore

@MainActor
final class AppStateGardenTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testFocusSessionSettlesGarden() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = DataStore(inMemory: true)
        let state = AppState(
            store: store,
            calendar: cal,
            remindersProvider: MockRemindersProvider(),
            schedulesRemindersSync: false,
            observeSystemEvents: false
        )
        XCTAssertNotNil(state.gardenSnapshot)
        XCTAssertEqual(state.gardenSnapshot?.slots.count, 3)

        store.insert(FocusSession(endedAt: now, minutes: 25, completed: true))
        store.save()
        state.refresh(now: now)

        XCTAssertEqual(state.gardenSnapshot?.slots.first?.cropID, "parsnip")
        XCTAssertEqual(state.gardenSnapshot?.coins, 1)
        XCTAssertEqual(state.gardenSnapshot?.companionMood, .happy)
    }

    func testPurchaseGardenItem() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = DataStore(inMemory: true)
        let garden = try! store.gardenMeta()
        garden.coins = 20
        store.save()
        let state = AppState(
            store: store,
            calendar: cal,
            remindersProvider: MockRemindersProvider(),
            schedulesRemindersSync: false,
            observeSystemEvents: false
        )
        XCTAssertTrue(state.purchaseGardenItem(GardenCatalog.itemFence))
        XCTAssertTrue(state.gardenSnapshot?.hasFence ?? false)
    }
}
