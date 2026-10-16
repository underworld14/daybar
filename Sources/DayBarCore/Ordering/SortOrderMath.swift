import Foundation

/// Fractional ordering: a moved task takes the midpoint between its new neighbours, so a
/// move writes one row. When repeated halving exhausts the gap, callers renormalize.
public enum SortOrderMath {
    /// Spacing between consecutive tasks after a backfill or renormalize.
    public static let step: Double = 1024
    /// Below this gap a midpoint is no longer trustworthy.
    public static let minimumGap: Double = 1e-7

    /// A value strictly between `lower` and `upper` (either may be open), or `nil` when the
    /// gap is exhausted or the bounds are out of order.
    public static func between(_ lower: Double?, _ upper: Double?) -> Double? {
        switch (lower, upper) {
        case (nil, nil):
            return nil
        case (let lower?, nil):
            return lower + step
        case (nil, let upper?):
            return upper - step
        case (let lower?, let upper?):
            guard upper - lower > minimumGap else { return nil }
            let mid = lower + (upper - lower) / 2
            guard mid > lower, mid < upper else { return nil }
            return mid
        }
    }

    /// Evenly spaced values for `count` tasks in order: step, 2·step, …
    public static func spaced(count: Int) -> [Double] {
        (0..<count).map { Double($0 + 1) * step }
    }
}
