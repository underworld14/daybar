import Foundation

/// Sparkle update feed settings shared by the app and tests.
public enum UpdateConfiguration {
    public static let feedURL = URL(string: "https://underworld14.github.io/daybar/appcast.xml")!
    /// Once per day — matches `SUScheduledCheckInterval` in Info.plist.
    public static let scheduledCheckInterval: TimeInterval = 86_400

    /// Returns true when `version` is newer than `current` using numeric semver comparison.
    public static func isNewerVersion(_ version: String, than current: String) -> Bool {
        compareVersions(version, current) == .orderedDescending
    }

    /// Numeric semver comparison (`0.3.0` vs `0.10.0`).
    public static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }
}
