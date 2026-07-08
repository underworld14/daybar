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
}
