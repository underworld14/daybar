import XCTest
@testable import DayBarCore

final class DropInsertionMathTests: XCTestCase {
    private let frames: [DropInsertionMath.RowFrame?] = [(0, 20), (24, 44), (48, 68)]

    func testIndexFromPointer() {
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 0, rowFrames: frames), 0)
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 12, rowFrames: frames), 1)
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 57, rowFrames: frames), 2)
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 80, rowFrames: frames), 3)
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 5, rowFrames: []), 0)
    }

    func testUnmeasuredRowsKeepTheirSlots() {
        // Rows 0–1 scrolled away (no frame); the pointer is over row 2's top half.
        let partial: [DropInsertionMath.RowFrame?] = [nil, nil, (100, 120), (124, 144), nil]
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 105, rowFrames: partial), 2)
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 130, rowFrames: partial), 3)
        // Below the last measured row (row 4 unmeasured further down): insert after row 3.
        XCTAssertEqual(DropInsertionMath.insertionIndex(locationY: 150, rowFrames: partial), 4)
        XCTAssertEqual(DropInsertionMath.indicatorY(for: 2, rowFrames: partial), 100)
        XCTAssertEqual(DropInsertionMath.indicatorY(for: 4, rowFrames: partial), 144)
    }

    func testClampToSegment() {
        XCTAssertEqual(DropInsertionMath.clamp(5, toSegmentCount: 2), 2)
        XCTAssertEqual(DropInsertionMath.clamp(-1, toSegmentCount: 2), 0)
        XCTAssertEqual(DropInsertionMath.clamp(1, toSegmentCount: 2), 1)
    }

    func testIndicatorSitsInTheGap() {
        XCTAssertEqual(DropInsertionMath.indicatorY(for: 0, rowFrames: frames), 0)
        XCTAssertEqual(DropInsertionMath.indicatorY(for: 1, rowFrames: frames), 22)
        XCTAssertEqual(DropInsertionMath.indicatorY(for: 3, rowFrames: frames), 68)
        XCTAssertNil(DropInsertionMath.indicatorY(for: 0, rowFrames: []))
    }
}
