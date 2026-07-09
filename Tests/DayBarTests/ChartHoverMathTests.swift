import XCTest
@testable import DayBarCore

final class ChartHoverMathTests: XCTestCase {
    private let day: TimeInterval = 86_400

    func testPicksExactMatch() {
        let base = Date(timeIntervalSince1970: 0)
        let candidates = [base, base.addingTimeInterval(day), base.addingTimeInterval(2 * day)]
        XCTAssertEqual(ChartHoverMath.nearestDate(to: candidates[1], in: candidates), candidates[1])
    }

    func testPicksClosestWhenBetweenTwoCandidates() {
        let base = Date(timeIntervalSince1970: 0)
        let candidates = [base, base.addingTimeInterval(day)]
        let target = base.addingTimeInterval(day * 0.9)
        XCTAssertEqual(ChartHoverMath.nearestDate(to: target, in: candidates), candidates[1])
    }

    func testPicksEarlierCandidateWhenCloser() {
        let base = Date(timeIntervalSince1970: 0)
        let candidates = [base, base.addingTimeInterval(day)]
        let target = base.addingTimeInterval(day * 0.1)
        XCTAssertEqual(ChartHoverMath.nearestDate(to: target, in: candidates), candidates[0])
    }

    func testReturnsNilForEmptyCandidates() {
        XCTAssertNil(ChartHoverMath.nearestDate(to: Date(), in: []))
    }

    func testClampsTooltipCenterXInsidePlot() {
        let plot = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(ChartHoverMath.clampedTooltipCenterX(100, in: plot), 100, accuracy: 0.001)
    }

    func testClampsTooltipCenterXAtLeftEdge() {
        let plot = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(ChartHoverMath.clampedTooltipCenterX(10, in: plot), 40, accuracy: 0.001)
    }

    func testClampsTooltipCenterXAtRightEdge() {
        let plot = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(ChartHoverMath.clampedTooltipCenterX(190, in: plot), 160, accuracy: 0.001)
    }
}
