import XCTest
@testable import DayBarCore

/// Table-tests every `MoodAIAvailability` state against the pure UI gate, so the
/// end-of-day review's branching is verified without SwiftUI, a real device, or an
/// Apple-Intelligence-eligible Mac. Runs on any CI machine.
final class MoodAvailabilityTests: XCTestCase {
    private let longReflection = "Today was a genuinely good day at work"
    private let shortReflection = "fine"

    func testAvailableAndEnabledWithEnoughWordsAttemptsClassification() {
        XCTAssertTrue(MoodAIGate.shouldAttemptClassification(
            availability: .available, aiEnabled: true, reflection: longReflection
        ))
    }

    func testOsTooOldNeverAttempts() {
        XCTAssertFalse(MoodAIGate.shouldAttemptClassification(
            availability: .unavailable(.osTooOld), aiEnabled: true, reflection: longReflection
        ))
    }

    func testDeviceNotEligibleNeverAttempts() {
        XCTAssertFalse(MoodAIGate.shouldAttemptClassification(
            availability: .unavailable(.deviceNotEligible), aiEnabled: true, reflection: longReflection
        ))
    }

    func testAppleIntelligenceNotEnabledNeverAttempts() {
        XCTAssertFalse(MoodAIGate.shouldAttemptClassification(
            availability: .unavailable(.appleIntelligenceNotEnabled), aiEnabled: true, reflection: longReflection
        ))
    }

    func testModelNotReadyNeverAttempts() {
        XCTAssertFalse(MoodAIGate.shouldAttemptClassification(
            availability: .unavailable(.modelNotReady), aiEnabled: true, reflection: longReflection
        ))
    }

    func testUserDisabledPreferenceNeverAttemptsEvenWhenAvailable() {
        XCTAssertFalse(MoodAIGate.shouldAttemptClassification(
            availability: .available, aiEnabled: false, reflection: longReflection
        ))
    }

    func testShortReflectionSkipsAI() {
        XCTAssertFalse(MoodAIGate.shouldAttemptClassification(
            availability: .available, aiEnabled: true, reflection: shortReflection
        ))
    }

    func testEmptyReflectionSkipsAI() {
        XCTAssertFalse(MoodAIGate.shouldAttemptClassification(
            availability: .available, aiEnabled: true, reflection: ""
        ))
    }

    func testMockCheckerReflectsInjectedState() {
        let mock = MockMoodAIChecker(availability: .unavailable(.modelNotReady))
        XCTAssertEqual(mock.availability, .unavailable(.modelNotReady))
    }

    // MARK: - "1 entry = 1 day, immutable"

    func testReopeningAlreadyReviewedDayNeverReclassifiesWhenUnchanged() {
        XCTAssertFalse(MoodAIGate.shouldAttemptClassification(
            availability: .available, aiEnabled: true, reflection: longReflection,
            alreadyReviewed: true, savedReflection: longReflection
        ))
    }

    func testReopeningAlreadyReviewedDayReclassifiesWhenReflectionEdited() {
        XCTAssertTrue(MoodAIGate.shouldAttemptClassification(
            availability: .available, aiEnabled: true, reflection: longReflection + " and more",
            alreadyReviewed: true, savedReflection: longReflection
        ))
    }

    func testReopeningAlreadyReviewedDayReclassifiesOnExplicitRequest() {
        XCTAssertTrue(MoodAIGate.shouldAttemptClassification(
            availability: .available, aiEnabled: true, reflection: longReflection,
            alreadyReviewed: true, savedReflection: longReflection, explicitRequest: true
        ))
    }

    func testFirstTimeReviewStillAttemptsByDefault() {
        XCTAssertTrue(MoodAIGate.shouldAttemptClassification(
            availability: .available, aiEnabled: true, reflection: longReflection, alreadyReviewed: false
        ))
    }

    // MARK: - Applying a late AI suggestion

    func testSuggestionAppliesWhenNotCancelledAndNoManualPick() {
        XCTAssertTrue(MoodAIGate.shouldApplySuggestion(
            isCancelled: false, currentSource: .none, classifiedReflection: longReflection
        ))
    }

    func testSuggestionAppliesOverAPriorAISuggestion() {
        // A newer AI suggestion is allowed to replace an older one.
        XCTAssertTrue(MoodAIGate.shouldApplySuggestion(
            isCancelled: false, currentSource: .ai, classifiedReflection: longReflection
        ))
    }

    func testSuggestionNeverOverwritesManualPickForSameReflection() {
        XCTAssertFalse(MoodAIGate.shouldApplySuggestion(
            isCancelled: false,
            currentSource: .manual,
            reflectionAtManualPick: longReflection,
            classifiedReflection: longReflection
        ))
    }

    func testSuggestionOverwritesManualPickOnExplicitRequest() {
        XCTAssertTrue(MoodAIGate.shouldApplySuggestion(
            isCancelled: false,
            currentSource: .manual,
            reflectionAtManualPick: longReflection,
            classifiedReflection: longReflection,
            explicitRequest: true
        ))
    }

    func testSuggestionOverwritesManualPickWhenReflectionChanged() {
        XCTAssertTrue(MoodAIGate.shouldApplySuggestion(
            isCancelled: false,
            currentSource: .manual,
            reflectionAtManualPick: longReflection,
            classifiedReflection: longReflection + " extra"
        ))
    }

    func testSuggestionAppliesForLoadedManualMoodWhenReflectionEdited() {
        // Reopened review: moodSource is .manual with reflectionAtManualPick restored from disk.
        XCTAssertTrue(MoodAIGate.shouldApplySuggestion(
            isCancelled: false,
            currentSource: .manual,
            reflectionAtManualPick: longReflection,
            classifiedReflection: longReflection + " extra"
        ))
    }

    func testCancelledSuggestionIsDiscardedEvenWithoutManualPick() {
        XCTAssertFalse(MoodAIGate.shouldApplySuggestion(
            isCancelled: true, currentSource: .none, classifiedReflection: longReflection
        ))
    }

    func testHasEnoughTextForClassification() {
        XCTAssertTrue(MoodAIGate.hasEnoughTextForClassification(longReflection))
        XCTAssertFalse(MoodAIGate.hasEnoughTextForClassification(shortReflection))
    }
}
