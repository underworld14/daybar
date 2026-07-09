import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The only file that touches `FoundationModels` for the availability check. Maps Apple's
/// `SystemLanguageModel.Availability` onto our own `MoodAIAvailability`, so nothing else in
/// the app needs to import `FoundationModels` or care about its macOS-26-only availability.
///
/// When building with an SDK that lacks Foundation Models (e.g. Xcode 16 / macOS 15 SDK on CI),
/// availability reports `.osTooOld` so the rest of the app still compiles and ships.
public struct LiveMoodAIChecker: MoodAIAvailabilityChecking {
    public init() {}

    public var availability: MoodAIAvailability {
        #if canImport(FoundationModels)
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
        #else
        return .unavailable(.osTooOld)
        #endif
    }
}
