import XCTest
@testable import DayBarCore

final class MoodConfidenceAssessorTests: XCTestCase {
    func testLowSelfReportConfidence() {
        XCTAssertEqual(
            MoodConfidenceAssessor.assess(
                aiTag: .happy,
                aiConfidence: 2,
                reflection: "today was fine overall"
            ),
            .low
        )
    }

    func testIndonesianSadWithAIProudIsLow() {
        XCTAssertEqual(
            MoodConfidenceAssessor.assess(
                aiTag: .proud,
                aiConfidence: 5,
                reflection: "aku sangat sedih sekali"
            ),
            .low
        )
    }

    func testIndonesianHappyWithAIHappyIsHigh() {
        XCTAssertEqual(
            MoodConfidenceAssessor.assess(
                aiTag: .happy,
                aiConfidence: 4,
                reflection: "aku sangat senang sekali"
            ),
            .high
        )
    }

    func testNeutralWithKeywordIsLow() {
        XCTAssertEqual(
            MoodConfidenceAssessor.assess(
                aiTag: .neutral,
                aiConfidence: 5,
                reflection: "aku sangat sedih sekali"
            ),
            .low
        )
    }

    func testNoKeywordSignalIsHigh() {
        XCTAssertEqual(
            MoodConfidenceAssessor.assess(
                aiTag: .productive,
                aiConfidence: 4,
                reflection: "today was fine overall"
            ),
            .high
        )
    }

    func testSamePolarityDifferentTagIsHigh() {
        XCTAssertEqual(
            MoodConfidenceAssessor.assess(
                aiTag: .proud,
                aiConfidence: 4,
                reflection: "aku sangat senang sekali"
            ),
            .high
        )
    }
}
