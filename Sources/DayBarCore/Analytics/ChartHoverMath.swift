import Foundation
import CoreGraphics

/// Pure nearest-date lookup used by the Analytics chart hover overlay. Kept dependency-free
/// (no Charts/SwiftUI) so it's unit-testable without a rendered chart.
public enum ChartHoverMath {
    /// Picks whichever candidate date is closest in time to `target`. `nil` only when
    /// `candidates` is empty.
    public static func nearestDate(to target: Date, in candidates: [Date]) -> Date? {
        candidates.min { abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target)) }
    }

    /// Clamps a tooltip center-x so its edges stay inside `plotFrame` (assumes ~80pt width).
    public static func clampedTooltipCenterX(
        _ centerX: CGFloat,
        in plotFrame: CGRect,
        estimatedHalfWidth: CGFloat = 40
    ) -> CGFloat {
        let minX = plotFrame.minX + estimatedHalfWidth
        let maxX = plotFrame.maxX - estimatedHalfWidth
        guard minX <= maxX else { return plotFrame.midX }
        return min(max(centerX, minX), maxX)
    }
}
