import XCTest
@testable import DayBarCore

final class SortOrderMathTests: XCTestCase {
    func testBetweenOpenBounds() {
        XCTAssertNil(SortOrderMath.between(nil, nil))
        XCTAssertEqual(SortOrderMath.between(1024, nil), 2048)
        XCTAssertEqual(SortOrderMath.between(nil, 1024), 0)
    }

    func testBetweenIsTheMidpoint() {
        XCTAssertEqual(SortOrderMath.between(1024, 2048), 1536)
    }

    func testBetweenRejectsExhaustedOrInvertedGaps() {
        XCTAssertNil(SortOrderMath.between(1, 1 + 1e-12))
        XCTAssertNil(SortOrderMath.between(5, 5))
        XCTAssertNil(SortOrderMath.between(6, 5))
    }

    func testSpacedValues() {
        XCTAssertEqual(SortOrderMath.spaced(count: 3), [1024, 2048, 3072])
        XCTAssertEqual(SortOrderMath.spaced(count: 0), [])
    }
}
