import XCTest
@testable import DayBarCore

/// Farm-animal economy: production is driven ONLY by completed focus sessions (never idle time),
/// collecting is the sole coin path, and everything stays backup-compatible.
final class GardenAnimalTests: XCTestCase {
    private var cal: Calendar!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        cal = c
    }

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    }

    private func session(_ offset: Int = 0, completed: Bool = true) -> FocusSession {
        FocusSession(endedAt: day(offset).addingTimeInterval(10 * 3600), minutes: 25, completed: completed)
    }

    private func sessions(_ count: Int, completed: Bool = true) -> [FocusSession] {
        (0..<count).map { _ in session(0, completed: completed) }
    }

    /// Settled today so wilt never interferes with the animal assertions.
    private func meta() -> GardenMeta {
        let m = GardenMeta()
        m.lastSettledDay = day(0)
        return m
    }

    // MARK: - Production on focus (not idle)

    func testProductionAdvancesOnCompletedSessionsOnly() {
        let m = meta()
        m.animals = [OwnedAnimal(kind: .chicken, energyUntilReady: 3, cell: 0, acquiredAt: now)]
        GardenEngine.settle(meta: m, sessions: sessions(3), asOf: now, calendar: cal)
        XCTAssertEqual(m.animals.first?.energyUntilReady, 0)
        XCTAssertEqual(m.animals.first?.hasProduct, true)
    }

    func testProductionIgnoresIncompleteAndIdle() {
        let m = meta()
        m.animals = [OwnedAnimal(kind: .chicken, energyUntilReady: 3, cell: 0, acquiredAt: now)]
        // Only incomplete sessions ⇒ newEnergy 0 ⇒ no advance.
        GardenEngine.settle(meta: m, sessions: sessions(5, completed: false), asOf: now, calendar: cal)
        XCTAssertEqual(m.animals.first?.energyUntilReady, 3)
        XCTAssertEqual(m.animals.first?.hasProduct, false)
    }

    func testZeroCompletedSessionsYieldsZeroAnimalProductionAndZeroCoins() {
        let m = meta()
        m.coins = 90
        m.animals = [OwnedAnimal(kind: .chicken, energyUntilReady: 3, cell: 0, acquiredAt: now)]
        GardenEngine.settle(meta: m, sessions: [], asOf: now, calendar: cal)
        XCTAssertEqual(m.coins, 90)                     // no coins without focus
        XCTAssertEqual(m.animals.first?.energyUntilReady, 3)
        XCTAssertEqual(m.animals.first?.hasProduct, false)
        XCTAssertEqual(m.lifetimeCompletedSessions, 0)
    }

    func testProductionIdempotentReSettle() {
        let m = meta()
        m.animals = [OwnedAnimal(kind: .sheep, energyUntilReady: 8, cell: 0, acquiredAt: now)]
        GardenEngine.settle(meta: m, sessions: sessions(3), asOf: now, calendar: cal)
        XCTAssertEqual(m.animals.first?.energyUntilReady, 5)
        // Re-settle the SAME sessions ⇒ newEnergy 0 ⇒ no further advance.
        GardenEngine.settle(meta: m, sessions: sessions(3), asOf: now, calendar: cal)
        XCTAssertEqual(m.animals.first?.energyUntilReady, 5)
    }

    func testAnimalReadyEmitsRewardEntryDuringSettle() {
        let m = meta()
        m.animals = [OwnedAnimal(kind: .chicken, energyUntilReady: 3, cell: 0, acquiredAt: now)]
        GardenEngine.settle(meta: m, sessions: sessions(3), asOf: now, calendar: cal)
        XCTAssertTrue(m.recentRewards.contains { $0.kind == .animalReady && $0.coinDelta == 0 })
    }

    // MARK: - Collect

    func testCollectClearsAddsCoinsResetsTimer() {
        let m = meta()
        m.coins = 5
        let animal = OwnedAnimal(kind: .chicken, energyUntilReady: 0, cell: 0, acquiredAt: now)
        m.animals = [animal]
        let reward = GardenEngine.collectFromAnimal(meta: m, animalID: animal.id, asOf: now, calendar: cal)
        XCTAssertNotNil(reward)
        XCTAssertEqual(reward?.kind, .collected)
        XCTAssertEqual(reward?.coinDelta, 2)
        XCTAssertEqual(m.coins, 7)                       // 5 + chicken collectValue 2
        XCTAssertEqual(m.animals.first?.energyUntilReady, 3)  // reset to productionEnergy
        XCTAssertEqual(m.animals.first?.hasProduct, false)
    }

    func testCollectInvalidIsNoOp() {
        let m = meta()
        m.coins = 10
        let notReady = OwnedAnimal(kind: .cow, energyUntilReady: 4, cell: 0, acquiredAt: now)
        m.animals = [notReady]
        let before = m.animalsJSON
        XCTAssertNil(GardenEngine.collectFromAnimal(meta: m, animalID: notReady.id, asOf: now, calendar: cal))
        XCTAssertNil(GardenEngine.collectFromAnimal(meta: m, animalID: UUID(), asOf: now, calendar: cal))
        XCTAssertEqual(m.coins, 10)
        XCTAssertEqual(m.animalsJSON, before)
        XCTAssertTrue(m.recentRewards.isEmpty)
    }

    func testCollectNeverTouchesLifetimeOrLastSettled() {
        let m = meta()
        m.lifetimeCompletedSessions = 7
        let settledDay = m.lastSettledDay
        let animal = OwnedAnimal(kind: .sheep, energyUntilReady: 0, cell: 0, acquiredAt: now)
        m.animals = [animal]
        GardenEngine.collectFromAnimal(meta: m, animalID: animal.id, asOf: now, calendar: cal)
        XCTAssertEqual(m.lifetimeCompletedSessions, 7)
        XCTAssertEqual(m.lastSettledDay, settledDay)
    }

    // MARK: - Buy

    func testBuyDeductsAppendsAssignsCell() {
        let m = GardenMeta()
        m.coins = 15
        let result = GardenShop.buyAnimal(kind: .chicken, meta: m, asOf: now)
        XCTAssertTrue(result.success)
        XCTAssertEqual(m.coins, 5)                       // 15 - 10
        XCTAssertEqual(m.animals.count, 1)
        XCTAssertEqual(m.animals.first?.cell, 0)
        XCTAssertEqual(m.animals.first?.energyUntilReady, 3)   // freshly bought = not ready
        XCTAssertEqual(m.animals.first?.hasProduct, false)
        XCTAssertEqual(result.animalID, m.animals.first?.id)
    }

    func testBuyInsufficientCoinsNoOp() {
        let m = GardenMeta()
        m.coins = 5
        let result = GardenShop.buyAnimal(kind: .cow, meta: m, asOf: now)   // cow costs 20
        XCTAssertFalse(result.success)
        XCTAssertEqual(m.coins, 5)
        XCTAssertTrue(m.animals.isEmpty)
    }

    func testBuyCapacityFull() {
        let m = GardenMeta()
        m.coins = 1000
        for _ in 0..<GardenAnimalCatalog.maxAnimals {
            XCTAssertTrue(GardenShop.buyAnimal(kind: .chicken, meta: m, asOf: now).success)
        }
        let overflow = GardenShop.buyAnimal(kind: .chicken, meta: m, asOf: now)
        XCTAssertFalse(overflow.success)
        XCTAssertEqual(m.animals.count, GardenAnimalCatalog.maxAnimals)
        // Distinct pen cells assigned.
        XCTAssertEqual(Set(m.animals.compactMap(\.cell)).count, GardenAnimalCatalog.maxAnimals)
    }

    // MARK: - Persistence

    func testAnimalsJSONRoundTrip() {
        let animals = [
            OwnedAnimal(kind: .chicken, energyUntilReady: 2, cell: 0, acquiredAt: now),
            OwnedAnimal(kind: .cow, energyUntilReady: 0, cell: 1, acquiredAt: now),
        ]
        let json = GardenMeta.encodeAnimals(animals)
        XCTAssertNotNil(json)
        let decoded = GardenMeta.decodeAnimals(json!)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].kind, .chicken)
        XCTAssertEqual(decoded[0].energyUntilReady, 2)
        XCTAssertEqual(decoded[1].kind, .cow)
        XCTAssertEqual(decoded[1].hasProduct, true)
    }
}
