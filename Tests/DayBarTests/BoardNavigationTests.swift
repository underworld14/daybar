import XCTest
@testable import DayBarCore

final class BoardNavigationTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()

    /// To Do: a b c · In Progress: (empty) · Done: d e
    private var board: [[UUID]] { [[a, b, c], [], [d, e]] }

    func testNoSelectionStartsAtTheEdges() {
        XCTAssertEqual(BoardNavigation.next(from: nil, in: board, direction: .down), a)
        XCTAssertEqual(BoardNavigation.next(from: nil, in: board, direction: .up), e)
        XCTAssertNil(BoardNavigation.next(from: nil, in: [[], []], direction: .down))
    }

    func testUpDownStayInsideTheColumn() {
        XCTAssertEqual(BoardNavigation.next(from: b, in: board, direction: .down), c)
        XCTAssertEqual(BoardNavigation.next(from: c, in: board, direction: .down), c)
        XCTAssertEqual(BoardNavigation.next(from: a, in: board, direction: .up), a)
    }

    func testLeftRightSkipEmptyColumnsAndKeepTheRow() {
        XCTAssertEqual(BoardNavigation.next(from: b, in: board, direction: .right), e)
        XCTAssertEqual(BoardNavigation.next(from: a, in: board, direction: .right), d)
        XCTAssertEqual(BoardNavigation.next(from: e, in: board, direction: .left), b)
        XCTAssertEqual(BoardNavigation.next(from: a, in: board, direction: .left), a)
    }

    func testUnknownSelectionRestarts() {
        XCTAssertEqual(BoardNavigation.next(from: UUID(), in: board, direction: .down), a)
    }
}
