import Foundation
@testable import DayBarCore

/// Lets tests simulate every `MoodAIAvailability` state without a real device or
/// `FoundationModels` — mirrors `MockRemindersProvider`.
final class MockMoodAIChecker: MoodAIAvailabilityChecking {
    var availability: MoodAIAvailability

    init(availability: MoodAIAvailability = .available) {
        self.availability = availability
    }
}
