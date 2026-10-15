import Foundation

/// Sizing rules for the menu-bar panel. The tray reports its measured heights (whole root,
/// the scroll viewport, and the scroll content); the panel grows to show all content
/// without scrolling, within a floor and 80% of the screen.
public enum TrayLayoutPolicy {
    public static let minimumHeight: Double = 280
    public static let maximumScreenFraction: Double = 0.8

    /// - Parameters:
    ///   - rootHeight: measured height of the whole panel content.
    ///   - viewportHeight: measured height of the scrolling region as currently laid out.
    ///   - contentHeight: measured natural height of the scrolling content.
    ///   - screenHeight: visible height of the screen the panel is on.
    public static func desiredHeight(
        rootHeight: Double,
        viewportHeight: Double,
        contentHeight: Double,
        screenHeight: Double
    ) -> Double {
        let chrome = max(0, rootHeight - viewportHeight)
        let natural = chrome + max(0, contentHeight)
        let ceiling = max(minimumHeight, screenHeight * maximumScreenFraction)
        return min(max(natural, minimumHeight), ceiling).rounded()
    }
}
