import Foundation

/// Pure decision of whether the end-of-day review sheet should auto-present — extracted out
/// of `AppState` so the snooze and focus-session-aware rules are unit-testable without
/// SwiftUI or a running `PomodoroEngine`.
public enum EndOfDayReviewGate {
    /// - Parameters:
    ///   - snoozedUntil: set by the user tapping "Not now"; `nil` once that window has passed.
    ///   - isFocusSessionRunning: an active Pomodoro work phase — the review is deliberately
    ///     never forced on top of a focus session the user is still in.
    public static func shouldPresent(
        hasReviewedToday: Bool,
        totalTodayCount: Int,
        now: Date,
        eveningTime: Date,
        snoozedUntil: Date?,
        isFocusSessionRunning: Bool
    ) -> Bool {
        guard !hasReviewedToday, totalTodayCount > 0, now >= eveningTime else { return false }
        if let snoozedUntil, now < snoozedUntil { return false }
        return !isFocusSessionRunning
    }
}
