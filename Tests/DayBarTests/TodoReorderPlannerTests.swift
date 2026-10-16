import XCTest
@testable import DayBarCore

final class TodoReorderPlannerTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    private var list: [ReorderSlot] {
        [ReorderSlot(id: a, sortOrder: 1024), ReorderSlot(id: b, sortOrder: 2048),
         ReorderSlot(id: c, sortOrder: 3072), ReorderSlot(id: d, sortOrder: 4096)]
    }

    func testMoveUpLandsBetweenNewNeighbours() {
        // c → before b
        XCTAssertEqual(TodoReorderPlanner.placement(moving: c, toIndex: 1, within: list), .value(1536))
    }

    func testMoveDownUsesOnMoveIndexSemantics() {
        // a → after c (onMove passes 3 = "before d" in the original list)
        XCTAssertEqual(TodoReorderPlanner.placement(moving: a, toIndex: 3, within: list), .value(3584))
    }

    func testMoveToTopAndBottom() {
        XCTAssertEqual(TodoReorderPlanner.placement(moving: c, toIndex: 0, within: list), .value(0))
        XCTAssertEqual(TodoReorderPlanner.placement(moving: a, toIndex: 4, within: list), .value(5120))
    }

    func testMovingOntoItselfIsUnchanged() {
        XCTAssertEqual(TodoReorderPlanner.placement(moving: b, toIndex: 1, within: list), .unchanged)
        XCTAssertEqual(TodoReorderPlanner.placement(moving: b, toIndex: 2, within: list), .unchanged)
    }

    func testAloneIsUnchanged() {
        let solo = [ReorderSlot(id: a, sortOrder: 7)]
        XCTAssertEqual(TodoReorderPlanner.placement(moving: a, toIndex: 0, within: solo), .unchanged)
    }

    func testDroppedInFromAnotherListLandsAtIndex() {
        let outsider = UUID()
        XCTAssertEqual(TodoReorderPlanner.placement(moving: outsider, toIndex: 2, within: list), .value(2560))
    }

    func testExhaustedGapAsksForRenormalize() {
        let tight = [ReorderSlot(id: a, sortOrder: 1), ReorderSlot(id: b, sortOrder: 1 + 1e-12),
                     ReorderSlot(id: c, sortOrder: 9)]
        XCTAssertEqual(TodoReorderPlanner.placement(moving: c, toIndex: 1, within: tight), .needsRenormalize)
    }

    func testEqualLegacyNeighboursAskForRenormalize() {
        let zeros = [ReorderSlot(id: a, sortOrder: 0), ReorderSlot(id: b, sortOrder: 0), ReorderSlot(id: c, sortOrder: 0)]
        XCTAssertEqual(TodoReorderPlanner.placement(moving: c, toIndex: 1, within: zeros), .needsRenormalize)
    }

    func testKeyboardIndexForOffsets() {
        XCTAssertEqual(TodoReorderPlanner.index(moving: c, by: -1, within: list), 1)
        XCTAssertEqual(TodoReorderPlanner.index(moving: b, by: 1, within: list), 3)
        XCTAssertNil(TodoReorderPlanner.index(moving: a, by: -1, within: list))
        XCTAssertNil(TodoReorderPlanner.index(moving: d, by: 1, within: list))
    }
}
