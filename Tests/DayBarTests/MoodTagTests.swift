import XCTest
@testable import DayBarCore

final class MoodTagTests: XCTestCase {
    func testScoreTableMatchesSpecExactly() {
        let expected: [MoodTag: Int] = [
            .lovestruck: 2, .proud: 2,
            .happy: 1, .productive: 1, .social: 1,
            .neutral: 0,
            .busyMeetings: -1, .tired: -1, .anxious: -1,
            .stressed: -2, .disappointed: -2,
        ]
        for tag in MoodTag.allCases {
            XCTAssertEqual(tag.score, expected[tag], "\(tag) has unexpected score")
        }
        XCTAssertEqual(MoodTag.allCases.count, 11)
    }

    func testRawValueRoundTrips() {
        for tag in MoodTag.allCases {
            XCTAssertEqual(MoodTag(rawValue: tag.rawValue), tag)
        }
    }

    func testUnknownRawValueHasNoCase() {
        XCTAssertNil(MoodTag(rawValue: "does-not-exist"))
    }

    func testDayLogFallsBackToNeutralForUnknownStoredTag() {
        let log = DayLog(day: .now)
        log.moodTagRaw = "some-legacy-value-that-no-longer-exists"
        XCTAssertNil(log.moodTag, "unknown raw values should decode to nil, not crash")
        XCTAssertNil(log.moodScore)
    }

    func testMoodScoreDerivesFromTag() {
        let log = DayLog(day: .now, moodTag: .stressed, moodSource: .manual)
        XCTAssertEqual(log.moodScore, -2)
        XCTAssertEqual(log.moodSource, .manual)
    }
}
