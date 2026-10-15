import XCTest
@testable import DayBarCore

final class DropInsertionMathTests: XCTestCase {
    private let mids: [Double] = [10, 30, 50]

    func testIndexFromPointer() {
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 0, rowMidYs: mids), 0)
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 12, rowMidYs: mids), 1)
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 49, rowMidYs: mids), 2)
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 80, rowMidYs: mids), 3)
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 5, rowMidYs: []), 0)
    }

    func testClampToSegment() {
        XCTAssertEqual(DropInsertionMath.clamp(5, toSegmentCount: 2), 2)
        XCTAssertEqual(DropInsertionMath.clamp(-1, toSegmentCount: 2), 0)
        XCTAssertEqual(DropInsertionMath.clamp(1, toSegmentCount: 2), 1)
    }

    func testIndicatorSitsInTheGap() {
        let frames: [(minY: Double, maxY: Double)] = [(0, 20), (24, 44), (48, 68)]
        XCTAssertEqual(DropInsertionMath.indicatorY(for: 0, rowFrames: frames), 0)
        XCTAssertEqual(DropInsertionMath.indicatorY(for: 1, rowFrames: frames), 22)
        XCTAssertEqual(DropInsertionMath.indicatorY(for: 3, rowFrames: frames), 68)
        XCTAssertNil(DropInsertionMath.indicatorY(for: 0, rowFrames: []))
    }
}
