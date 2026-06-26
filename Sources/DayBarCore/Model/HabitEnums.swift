import Foundation

/// Lifecycle status of a single habit log for one calendar day.
public enum HabitDayStatus: String, CaseIterable, Codable, Sendable {
    case pending
    case completed
    case skipped
}