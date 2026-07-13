import XCTest
@testable import DayBarCore

final class MoodTagAITagTests: XCTestCase {
    func testExactRawValues() {
        for tag in MoodTag.allCases {
            XCTAssertEqual(MoodTag.fromAITag(tag.rawValue), tag)
        }
    }

    func testCaseInsensitiveAndDisplayName() {
        XCTAssertEqual(MoodTag.fromAITag("Happy"), .happy)
        XCTAssertEqual(MoodTag.fromAITag("STRESSED"), .stressed)
        XCTAssertEqual(MoodTag.fromAITag("Busy meetings"), .busyMeetings)
    }

    func testUnknownFallsBackToNeutral() {
        XCTAssertEqual(MoodTag.fromAITag("senang"), .neutral)
        XCTAssertEqual(MoodTag.fromAITag(""), .neutral)
    }
}
