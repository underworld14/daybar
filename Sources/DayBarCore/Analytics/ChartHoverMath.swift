import Foundation

/// Pure nearest-date lookup used by the Analytics chart hover overlay. Kept dependency-free
/// (no Charts/SwiftUI) so it's unit-testable without a rendered chart.
public enum ChartHoverMath {
    /// Picks whichever candidate date is closest in time to `target`. `nil` only when
    /// `candidates` is empty.
    public static func nearestDate(to target: Date, in candidates: [Date]) -> Date? {
        candidates.min { abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target)) }
    }
}
