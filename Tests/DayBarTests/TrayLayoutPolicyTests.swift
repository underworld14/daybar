import XCTest
@testable import DayBarCore

final class TrayLayoutPolicyTests: XCTestCase {
    func testGrowsToFitContent() {
        // 300pt of chrome around a 200pt viewport whose content is 420pt tall.
        let height = TrayLayoutPolicy.desiredHeight(
            rootHeight: 500, viewportHeight: 200, contentHeight: 420, screenHeight: 1_200
        )
        XCTAssertEqual(height, 720)
    }

    func testNeverShorterThanMinimum() {
        let height = TrayLayoutPolicy.desiredHeight(
            rootHeight: 200, viewportHeight: 50, contentHeight: 20, screenHeight: 1_200
        )
        XCTAssertEqual(height, TrayLayoutPolicy.minimumHeight)
    }

    func testCappedAtEightyPercentOfScreen() {
        let height = TrayLayoutPolicy.desiredHeight(
            rootHeight: 600, viewportHeight: 300, contentHeight: 2_000, screenHeight: 1_000
        )
        XCTAssertEqual(height, 800)
    }

    func testIgnoresNegativeMeasurements() {
        let height = TrayLayoutPolicy.desiredHeight(
            rootHeight: 100, viewportHeight: 300, contentHeight: -10, screenHeight: 1_000
        )
        XCTAssertEqual(height, TrayLayoutPolicy.minimumHeight)
    }
}
