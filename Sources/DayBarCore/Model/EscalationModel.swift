import Foundation

/// User-tunable day thresholds for the escalation tiers. Ships calm; the Settings
/// "intensity" control can lower these later to nudge harder.
public struct EscalationThresholds: Sendable, Equatable {
    public var slippedMinDays: Int
    public var agingMinDays: Int

    public init(slippedMinDays: Int = 1, agingMinDays: Int = 3) {
        self.slippedMinDays = slippedMinDays
        self.agingMinDays = agingMinDays
    }

    public static let gentle = EscalationThresholds(slippedMinDays: 1, agingMinDays: 3)
}

/// Pure mapping from a task's age (in days) to its escalation tier and visual hints.
/// Side-effect free and fully unit-testable; shared by the row UI and the menu-bar badge.
public enum EscalationModel {
    /// The tier for a task that is `age` days old.
    public static func tier(forAgeInDays age: Int, thresholds: EscalationThresholds = .gentle) -> EscalationTier {
        if age >= thresholds.agingMinDays { return .aging }
        if age >= thresholds.slippedMinDays { return .slipped }
        return .onPlan
    }

    /// Whether this tier contributes to the (amber) menu-bar count. Only genuinely
    /// aging items count — fresh slips keep the menu bar quiet.
    public static func countsTowardBadge(_ tier: EscalationTier) -> Bool {
        tier >= .aging
    }

    /// Compact age pill text (e.g. "3d"), or nil when the task isn't aged.
    public static func ageLabel(forAgeInDays age: Int) -> String? {
        age <= 0 ? nil : "\(age)d"
    }
}
