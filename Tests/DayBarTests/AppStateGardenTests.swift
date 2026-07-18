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

    private func utcCal() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testHarvestGardenSlotClearsAndPersists() {
        let cal = utcCal()
        let store = DataStore(inMemory: true)
        let garden = try! store.gardenMeta()
        garden.slots = [
            GardenPlotSlot(index: 0, cropID: "parsnip", stage: 4, plantedOn: now),
            GardenPlotSlot(index: 1),
            GardenPlotSlot(index: 2),
        ]
        garden.coins = 0
        store.save()
        let state = AppState(
            store: store, calendar: cal,
            remindersProvider: MockRemindersProvider(),
            schedulesRemindersSync: false, observeSystemEvents: false
        )
        XCTAssertTrue(state.harvestGardenSlot(0, now: now))
        XCTAssertEqual(state.gardenSnapshot?.slots.first?.isEmpty, true)
        XCTAssertEqual(state.gardenSnapshot?.coins, 2)          // harvest bonus
        XCTAssertEqual(state.gardenSnapshot?.recentRewards.first?.cropID, "parsnip")
        // Persisted to the store.
        XCTAssertEqual(try! store.gardenMeta().coins, 2)
    }

    func testPlantGardenSlotPlants() {
        let cal = utcCal()
        let store = DataStore(inMemory: true)
        let garden = try! store.gardenMeta()
        garden.slots = GardenPlotSlot.emptySlots()
        garden.lastPlantedCropID = "parsnip"
        garden.coins = 4
        store.save()
        let state = AppState(
            store: store, calendar: cal,
            remindersProvider: MockRemindersProvider(),
            schedulesRemindersSync: false, observeSystemEvents: false
        )
        XCTAssertTrue(state.plantGardenSlot(1, now: now))
        XCTAssertEqual(state.gardenSnapshot?.slots[1].cropID, "cauliflower")
        XCTAssertEqual(state.gardenSnapshot?.coins, 4)          // planting is free
    }

    func testHarvestInvalidSlotIsNoOp() {
        let cal = utcCal()
        let store = DataStore(inMemory: true)
        let garden = try! store.gardenMeta()
        garden.slots = GardenPlotSlot.emptySlots()   // nothing mature
        store.save()
        let state = AppState(
            store: store, calendar: cal,
            remindersProvider: MockRemindersProvider(),
            schedulesRemindersSync: false, observeSystemEvents: false
        )
        XCTAssertFalse(state.harvestGardenSlot(0, now: now))
    }
}
