import Foundation

/// Lifecycle status of a todo. Persisted via `statusRaw` (single source of truth);
/// the typed `status` accessor lives on `DailyTodo`.
public enum TodoStatus: String, CaseIterable, Codable, Sendable {
    case planned
    case completed
    case carriedOver
    case snoozed
    case dropped
}

/// Task priority. Backed by an `Int` rawValue so SwiftData can sort on it.
public enum Priority: Int, CaseIterable, Codable, Sendable, Comparable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where a todo originated. `reminders` is reserved for Phase 3 (EventKit).
public enum TodoSource: String, Codable, Sendable {
    case local
    case reminders
}

/// Gentle escalation tier for a carried-over task. Capped intentionally low for the
/// default ("gentle") intensity so the app never shouts.
public enum EscalationTier: Int, CaseIterable, Codable, Sendable, Comparable {
    case onPlan = 0   // age 0 — planned for today
    case slipped = 1  // 1–2 days old
    case aging = 2    // >= threshold (default 3 days) old

    public static func < (lhs: EscalationTier, rhs: EscalationTier) -> Bool { lhs.rawValue < rhs.rawValue }
}
