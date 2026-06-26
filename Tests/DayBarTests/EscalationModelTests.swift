import XCTest
@testable import DayBarCore

final class EscalationModelTests: XCTestCase {
    func testDefaultTierBoundaries() {
        XCTAssertEqual(EscalationModel.tier(forAgeInDays: 0), .onPlan)
        XCTAssertEqual(EscalationModel.tier(forAgeInDays: 1), .slipped)
        XCTAssertEqual(EscalationModel.tier(forAgeInDays: 2), .slipped)
        XCTAssertEqual(EscalationModel.tier(forAgeInDays: 3), .aging)
        XCTAssertEqual(EscalationModel.tier(forAgeInDays: 30), .aging)
    }

    func testCustomThresholds() {
        let t = EscalationThresholds(slippedMinDays: 2, agingMinDays: 5)
        XCTAssertEqual(EscalationModel.tier(forAgeInDays: 1, thresholds: t), .onPlan)
        XCTAssertEqual(EscalationModel.tier(forAgeInDays: 2, thresholds: t), .slipped)
        XCTAssertEqual(EscalationModel.tier(forAgeInDays: 5, thresholds: t), .aging)
    }

    func testBadgeAndLabel() {
        XCTAssertFalse(EscalationModel.countsTowardBadge(.slipped))
        XCTAssertTrue(EscalationModel.countsTowardBadge(.aging))
        XCTAssertNil(EscalationModel.ageLabel(forAgeInDays: 0))
        XCTAssertEqual(EscalationModel.ageLabel(forAgeInDays: 3), "3d")
    }
}
