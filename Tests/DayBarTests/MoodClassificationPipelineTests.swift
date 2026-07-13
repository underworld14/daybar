import XCTest
@testable import DayBarCore

final class MoodClassificationPipelineTests: XCTestCase {
    func testHighConfidenceAIResult() {
        let result = MoodClassificationPipeline.resolve(
            ai: MoodAIClassification(tag: .productive, confidence: 5),
            reflection: "today was fine overall",
            aiFailed: false
        )
        XCTAssertEqual(result?.tag, .productive)
        XCTAssertEqual(result?.source, .ai)
    }

    func testLowConfidencePolarityMismatchFallsBackToHeuristic() {
        let result = MoodClassificationPipeline.resolve(
            ai: MoodAIClassification(tag: .proud, confidence: 5),
            reflection: "aku sangat sedih sekali",
            aiFailed: false
        )
        XCTAssertEqual(result?.tag, .disappointed)
        XCTAssertEqual(result?.source, .heuristic)
    }

    func testLowConfidenceWithoutKeywordKeepsAI() {
        let result = MoodClassificationPipeline.resolve(
            ai: MoodAIClassification(tag: .anxious, confidence: 1),
            reflection: "today was fine overall",
            aiFailed: false
        )
        XCTAssertEqual(result?.tag, .anxious)
        XCTAssertEqual(result?.source, .ai)
    }

    func testAIFailureFallsBackToHeuristic() {
        let result = MoodClassificationPipeline.resolve(
            ai: nil,
            reflection: "aku sangat senang sekali",
            aiFailed: true
        )
        XCTAssertEqual(result?.tag, .happy)
        XCTAssertEqual(result?.source, .heuristic)
    }

    func testAIFailureWithoutKeywordReturnsNil() {
        XCTAssertNil(
            MoodClassificationPipeline.resolve(
                ai: nil,
                reflection: "hari ini biasa saja di kantor",
                aiFailed: true
            )
        )
    }
}
