import XCTest
@testable import DayBarCore

/// The tray's long-lived `NSHostingView` fails to mount a newly-inserted TOMORROW
/// section when the list goes from empty → non-empty (rows only appear after reopen).
/// Keep the section in the view tree even at count 0 so adds update in place.
final class TraySectionPolicyTests: XCTestCase {
    func testTomorrowSectionStaysMountedWhenEmpty() {
        XCTAssertTrue(
            TraySectionPolicy.showsTomorrowSection(todoCount: 0),
            "Empty tomorrow list must still mount the section so the first add is visible without reopening the tray"
        )
    }

    func testTomorrowSectionStaysMountedWhenNonEmpty() {
        XCTAssertTrue(TraySectionPolicy.showsTomorrowSection(todoCount: 1))
        XCTAssertTrue(TraySectionPolicy.showsTomorrowSection(todoCount: 3))
    }
}
