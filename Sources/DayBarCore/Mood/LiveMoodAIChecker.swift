import Foundation
import FoundationModels

/// The only file that touches `FoundationModels` for the availability check. Maps Apple's
/// `SystemLanguageModel.Availability` onto our own `MoodAIAvailability`, so nothing else in
/// the app needs to import `FoundationModels` or care about its macOS-26-only availability.
public struct LiveMoodAIChecker: MoodAIAvailabilityChecking {
    public init() {}

    public var availability: MoodAIAvailability {
        guard #available(macOS 26.0, *) else { return .unavailable(.osTooOld) }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            return .unavailable(.modelNotReady)
        case .unavailable:
            return .unavailable(.other)
        }
    }
}
