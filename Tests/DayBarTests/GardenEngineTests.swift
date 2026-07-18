import XCTest
@testable import DayBarCore

final class GardenEngineTests: XCTestCase {
    private var cal: Calendar!
    private let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 UTC-ish

    override func setUp() {
        super.setUp()
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        cal = c
    }

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    }

    private func session(_ offset: Int, completed: Bool = true) -> FocusSession {
        FocusSession(
            endedAt: day(offset).addingTimeInterval(10 * 3600),
            minutes: 25,
            completed: completed
        )
    }

    private func meta(settled offset: Int? = nil) -> GardenMeta {
        let m = GardenMeta()
        if let offset {
            m.lastSettledDay = day(offset)
        }
        return m
    }

    func testDefaultMetaHasThreeEmptySlots() {
        let m = GardenMeta()
        XCTAssertEqual(m.slots.count, 3)
        XCTAssertTrue(m.slots.allSatisfy(\.isEmpty))
    }

    func testSlotsJSONRoundTrip() {
        var slots = GardenPlotSlot.emptySlots()
        slots[0] = GardenPlotSlot(
            index: 0, cropID: "parsnip", stage: 2,
            plantedOn: day(0), lastGrownOn: day(0), wiltLevel: 1
        )
        let json = GardenMeta.encodeSlots(slots)
        XCTAssertNotNil(json)
        let decoded = GardenMeta.decodeSlots(json!)
        XCTAssertEqual(decoded[0].cropID, "parsnip")
        XCTAssertEqual(decoded[0].stage, 2)
        XCTAssertEqual(decoded[0].wiltLevel, 1)
    }

    func testCompletedSessionPlantsParsnip() {
        let m = meta(settled: 0)
        let snap = GardenEngine.settle(meta: m, sessions: [session(0)], asOf: now, calendar: cal)
        XCTAssertEqual(snap.slots[0].cropID, "parsnip")
        XCTAssertEqual(snap.slots[0].stage, 1)
        XCTAssertEqual(m.coins, 1)
        XCTAssertEqual(m.lifetimeCompletedSessions, 1)
        XCTAssertEqual(snap.companionMood, .happy)
    }

    func testIncompleteSessionIgnored() {
        let m = meta(settled: 0)
        let snap = GardenEngine.settle(
            meta: m,
            sessions: [session(0, completed: false)],
            asOf: now,
            calendar: cal
        )
        XCTAssertTrue(snap.slots.allSatisfy(\.isEmpty))
        XCTAssertEqual(m.coins, 0)
    }

    func testGrowthAdvancesStage() {
        let m = meta(settled: 0)
        let sessions = [session(0), session(0)]
        // First energy plants, second grows — but settle applies all new energy at once.
        _ = GardenEngine.settle(meta: m, sessions: [session(0)], asOf: now, calendar: cal)
        let snap = GardenEngine.settle(meta: m, sessions: sessions, asOf: now, calendar: cal)
        XCTAssertEqual(snap.slots[0].stage, 2)
        XCTAssertEqual(m.coins, 2)
    }

    func testSettleSameDayIdempotentNoDoubleWilt() {
        let m = meta(settled: -2)
        // Plant with focus yesterday so there is something to wilt if double-applied.
        m.slots = [
            GardenPlotSlot(index: 0, cropID: "parsnip", stage: 2, plantedOn: day(-3), wiltLevel: 0),
            GardenPlotSlot(index: 1),
            GardenPlotSlot(index: 2),
        ]
        m.lifetimeCompletedSessions = 1
        let sessions = [session(-3)]
        _ = GardenEngine.settle(meta: m, sessions: sessions, asOf: now, calendar: cal)
        let wiltAfterFirst = m.slots[0].wiltLevel
        _ = GardenEngine.settle(meta: m, sessions: sessions, asOf: now, calendar: cal)
        XCTAssertEqual(m.slots[0].wiltLevel, wiltAfterFirst)
    }

    func testSoftWiltOnMissWithoutGrace() {
        // Focus on day -3 only; settle from -2 so yesterday (-1) and -2 are empty misses.
        // Two misses: first may use grace, second wilts.
        let m = meta(settled: -3)
        m.slots = [
            GardenPlotSlot(index: 0, cropID: "parsnip", stage: 2, plantedOn: day(-3), wiltLevel: 0),
            GardenPlotSlot(index: 1),
            GardenPlotSlot(index: 2),
        ]
        m.lifetimeCompletedSessions = 1
        let sessions = [session(-3)]
        let snap = GardenEngine.settle(meta: m, sessions: sessions, asOf: now, calendar: cal)
        XCTAssertGreaterThanOrEqual(snap.slots[0].wiltLevel, 1)
    }

    func testGraceDayDoesNotWilt() {
        // Pattern from FocusAnalyticsTests: sessions on 0, -2, -3 → day -1 is grace.
        let m = meta(settled: -1) // will evaluate... wait lastSettled -1 means start from today only for wilt of days after -1 = none before today
        // Set lastSettled to -2 so we evaluate yesterday (-1) only once.
        m.lastSettledDay = day(-2)
        m.slots = [
            GardenPlotSlot(index: 0, cropID: "parsnip", stage: 2, plantedOn: day(-3), wiltLevel: 0),
            GardenPlotSlot(index: 1),
            GardenPlotSlot(index: 2),
        ]
        m.lifetimeCompletedSessions = 3
        let sessions = [session(0), session(-2), session(-3)]
        let snap = GardenEngine.settle(meta: m, sessions: sessions, asOf: now, calendar: cal)
        // Yesterday (-1) is grace → no wilt from that day; new energy today may plant more.
        // Wilt should stay 0 from grace.
        XCTAssertEqual(snap.slots[0].wiltLevel, 0)
    }

    func testSeasonFromCalendarMonth() {
        // November → autumn
        let m = meta(settled: 0)
        let snap = GardenEngine.settle(meta: m, sessions: [], asOf: now, calendar: cal)
        XCTAssertEqual(snap.season, .autumn)
        XCTAssertEqual(m.season, .autumn)
    }

    func testHarvestMatureGivesBonusCoins() {
        let m = meta(settled: 0)
        m.slots = [
            GardenPlotSlot(index: 0, cropID: "parsnip", stage: 4, plantedOn: day(-5), wiltLevel: 0),
            GardenPlotSlot(index: 1),
            GardenPlotSlot(index: 2),
        ]
        m.lifetimeCompletedSessions = 0
        let snap = GardenEngine.settle(meta: m, sessions: [session(0)], asOf: now, calendar: cal)
        XCTAssertTrue(snap.slots[0].isEmpty)
        XCTAssertEqual(snap.justHarvestedCropID, "parsnip")
        // +1 session coin +2 harvest bonus
        XCTAssertEqual(m.coins, 3)
        XCTAssertEqual(m.harvestLog.first?.cropID, "parsnip")
    }

    func testCropRotationOnNewPlant() {
        let m = meta(settled: 0)
        m.lastPlantedCropID = "parsnip"
        _ = GardenEngine.settle(meta: m, sessions: [session(0)], asOf: now, calendar: cal)
        XCTAssertEqual(m.slots[0].cropID, "cauliflower")
    }

    func testWeatherRainWhenTwoSessionsToday() {
        let m = meta(settled: 0)
        let sessions = [session(0), session(0)]
        let snap = GardenEngine.settle(meta: m, sessions: sessions, asOf: now, calendar: cal)
        XCTAssertEqual(snap.weather, .rain)
    }

    func testShopPurchaseAndIdempotent() {
        let m = GardenMeta()
        m.coins = 20
        let first = GardenShop.purchase(itemID: GardenCatalog.itemFence, meta: m)
        XCTAssertTrue(first.success)
        XCTAssertEqual(m.coins, 12)
        XCTAssertTrue(m.unlockedItemIDs.contains(GardenCatalog.itemFence))
        let second = GardenShop.purchase(itemID: GardenCatalog.itemFence, meta: m)
        XCTAssertFalse(second.success)
        XCTAssertTrue(second.alreadyOwned)
        XCTAssertEqual(m.coins, 12)
    }

    func testShopExtraSlotExpandsPlots() {
        let m = GardenMeta()
        m.coins = 20
        XCTAssertEqual(m.slots.count, 3)
        let result = GardenShop.purchase(itemID: GardenCatalog.itemExtraSlot, meta: m)
        XCTAssertTrue(result.success)
        XCTAssertEqual(m.slots.count, 4)
    }

    func testInsufficientCoinsNoOp() {
        let m = GardenMeta()
        m.coins = 2
        let result = GardenShop.purchase(itemID: GardenCatalog.itemFence, meta: m)
        XCTAssertFalse(result.success)
        XCTAssertEqual(m.coins, 2)
        XCTAssertTrue(m.unlockedItemIDs.isEmpty)
    }
}
