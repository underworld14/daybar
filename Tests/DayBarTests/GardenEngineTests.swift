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

    // MARK: - Action mode

    func testAutomaticModeUnchangedFullProgression() {
        let m = meta(settled: 0)
        let snap = GardenEngine.settle(meta: m, sessions: [session(0)], asOf: now, calendar: cal, mode: .automatic)
        XCTAssertEqual(snap.slots[0].cropID, "parsnip")
        XCTAssertEqual(snap.slots[0].stage, 1)
        XCTAssertEqual(m.coins, 1)
    }

    func testManualModeDoesNotAutoHarvestMature() {
        let m = meta(settled: 0)
        m.slots = [
            GardenPlotSlot(index: 0, cropID: "parsnip", stage: 4, plantedOn: day(-5), wiltLevel: 0),
            GardenPlotSlot(index: 1),
            GardenPlotSlot(index: 2),
        ]
        m.lifetimeCompletedSessions = 0
        let snap = GardenEngine.settle(meta: m, sessions: [session(0)], asOf: now, calendar: cal, mode: .manual)
        XCTAssertTrue(snap.slots[0].isMature)      // still ready — not auto-harvested
        XCTAssertNil(snap.justHarvestedCropID)
        XCTAssertEqual(m.coins, 1)                 // session coin only, no +2 bonus
        XCTAssertTrue(m.harvestLog.isEmpty)
    }

    func testManualModeGrowsButDoesNotPlant() {
        let m = meta(settled: 0)
        m.slots = [
            GardenPlotSlot(index: 0, cropID: "parsnip", stage: 1, plantedOn: day(-1), wiltLevel: 0),
            GardenPlotSlot(index: 1),
            GardenPlotSlot(index: 2),
        ]
        m.lifetimeCompletedSessions = 0
        let snap = GardenEngine.settle(meta: m, sessions: [session(0)], asOf: now, calendar: cal, mode: .manual)
        XCTAssertGreaterThanOrEqual(snap.slots[0].stage, 2)  // grew
        XCTAssertTrue(snap.slots[1].isEmpty)                 // not auto-planted
        XCTAssertTrue(snap.slots[2].isEmpty)
        XCTAssertEqual(m.coins, 1)
    }

    // MARK: - Manual intents

    func testManualHarvestClearsSlotAndAwardsBonus() {
        let m = GardenMeta()
        m.slots = [
            GardenPlotSlot(index: 0),
            GardenPlotSlot(index: 1, cropID: "parsnip", stage: 4, plantedOn: day(-5)),
            GardenPlotSlot(index: 2),
        ]
        m.coins = 0
        let entry = GardenEngine.harvest(meta: m, slotIndex: 1, asOf: now, calendar: cal)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.coinDelta, 2)
        XCTAssertEqual(entry?.cropID, "parsnip")
        XCTAssertEqual(entry?.kind, .harvested)
        XCTAssertTrue(m.slots[1].isEmpty)
        XCTAssertEqual(m.coins, 2)
        XCTAssertEqual(m.harvestLog.first?.cropID, "parsnip")
        XCTAssertEqual(m.recentRewards.first?.cropID, "parsnip")
        // Manual actions must not advance the focus-session projection.
        XCTAssertEqual(m.lifetimeCompletedSessions, 0)
    }

    func testManualPlantUsesRotationAndNoCoinCost() {
        let m = GardenMeta()
        m.lastPlantedCropID = "parsnip"
        m.coins = 5
        let entry = GardenEngine.plant(meta: m, slotIndex: 2, asOf: now, calendar: cal)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.coinDelta, 0)
        XCTAssertEqual(entry?.kind, .planted)
        XCTAssertEqual(m.slots[2].cropID, "cauliflower")
        XCTAssertEqual(m.slots[2].stage, 1)
        XCTAssertEqual(m.slots[2].wiltLevel, 0)
        XCTAssertEqual(m.coins, 5)                    // unchanged
        XCTAssertEqual(m.lastPlantedCropID, "cauliflower")
    }

    func testManualHarvestInvalidIsNoOp() {
        let m = GardenMeta()
        m.slots = [
            GardenPlotSlot(index: 0, cropID: "parsnip", stage: 2, plantedOn: day(-1)), // not mature
            GardenPlotSlot(index: 1),
            GardenPlotSlot(index: 2),
        ]
        m.coins = 7
        let slotsBefore = m.plotSlotsJSON
        XCTAssertNil(GardenEngine.harvest(meta: m, slotIndex: 0, asOf: now, calendar: cal)) // not mature
        XCTAssertNil(GardenEngine.harvest(meta: m, slotIndex: 9, asOf: now, calendar: cal)) // out of range
        XCTAssertEqual(m.coins, 7)
        XCTAssertEqual(m.plotSlotsJSON, slotsBefore)
        XCTAssertTrue(m.recentRewards.isEmpty)
    }

    func testManualPlantInvalidIsNoOp() {
        let m = GardenMeta()
        m.slots = [
            GardenPlotSlot(index: 0, cropID: "parsnip", stage: 2, plantedOn: day(-1)), // occupied
            GardenPlotSlot(index: 1),
            GardenPlotSlot(index: 2),
        ]
        m.coins = 3
        let slotsBefore = m.plotSlotsJSON
        XCTAssertNil(GardenEngine.plant(meta: m, slotIndex: 0, asOf: now, calendar: cal)) // occupied
        XCTAssertNil(GardenEngine.plant(meta: m, slotIndex: 9, asOf: now, calendar: cal)) // out of range
        XCTAssertEqual(m.coins, 3)
        XCTAssertEqual(m.plotSlotsJSON, slotsBefore)
        XCTAssertTrue(m.recentRewards.isEmpty)
    }

    // MARK: - Reward feed

    func testSettleRewardTextReportsCoinAndPlant() {
        let m = meta(settled: 0)
        let snap = GardenEngine.settle(meta: m, sessions: [session(0)], asOf: now, calendar: cal)
        let reward = snap.recentRewards.first
        XCTAssertNotNil(reward)
        XCTAssertEqual(reward?.coinDelta, 1)
        XCTAssertEqual(reward?.kind, .planted)
        XCTAssertEqual(reward?.seq, 1)
        XCTAssertTrue(reward!.text.contains("+1 coin"))
        XCTAssertTrue(reward!.text.contains("Parsnip planted"))
    }

    func testSettleRewardTextReportsHarvestAndBonusCoins() {
        let m = meta(settled: 0)
        m.slots = [
            GardenPlotSlot(index: 0, cropID: "parsnip", stage: 4, plantedOn: day(-5)),
            GardenPlotSlot(index: 1),
            GardenPlotSlot(index: 2),
        ]
        m.lifetimeCompletedSessions = 0
        let snap = GardenEngine.settle(meta: m, sessions: [session(0)], asOf: now, calendar: cal)
        let reward = snap.recentRewards.first
        XCTAssertEqual(reward?.coinDelta, 3)          // 1 session + 2 harvest bonus
        XCTAssertEqual(reward?.kind, .harvested)
        XCTAssertTrue(reward!.text.contains("Parsnip harvested"))
    }

    func testSettleRewardBatchPrecedenceHarvestWins() {
        let m = meta(settled: 0)
        m.slots = [
            GardenPlotSlot(index: 0, cropID: "parsnip", stage: 4, plantedOn: day(-5)),
            GardenPlotSlot(index: 1, cropID: "berry", stage: 1, plantedOn: day(-1)),
            GardenPlotSlot(index: 2),
        ]
        m.lifetimeCompletedSessions = 0
        let snap = GardenEngine.settle(meta: m, sessions: [session(0), session(0)], asOf: now, calendar: cal)
        let reward = snap.recentRewards.first
        XCTAssertEqual(reward?.kind, .harvested)      // harvest beats grow in the summary verb
        XCTAssertEqual(reward?.coinDelta, 4)          // 2 sessions + 1 harvest bonus
    }

    func testRewardFeedJSONRoundTrip() {
        let feed = [
            GardenRewardEntry(seq: 2, date: day(0), text: "Focus complete · +1 coin · Parsnip grew",
                              coinDelta: 1, kind: .grew, cropID: "parsnip"),
            GardenRewardEntry(seq: 1, date: day(-1), text: "Planted Berry",
                              coinDelta: 0, kind: .planted, cropID: "berry"),
        ]
        let json = GardenMeta.encodeRewardFeed(feed)
        XCTAssertNotNil(json)
        let decoded = GardenMeta.decodeRewardFeed(json!)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.first?.seq, 2)
        XCTAssertEqual(decoded.first?.kind, .grew)
        XCTAssertEqual(decoded.last?.cropID, "berry")
    }

    func testRewardFeedCapsAtEight() {
        let m = meta(settled: 0)
        for i in 1...10 {
            let sessions = (0..<i).map { _ in session(0) }
            _ = GardenEngine.settle(meta: m, sessions: sessions, asOf: now, calendar: cal)
        }
        XCTAssertEqual(m.recentRewards.count, GardenEngine.maxRewardFeedEntries)
        XCTAssertEqual(m.recentRewards.first?.seq, 10) // newest kept, monotonic seq
    }
}
