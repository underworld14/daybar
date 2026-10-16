import Observation
import DayBarCore

/// Live measurements of the tray content, reported by `TodayView` and read by the panel
/// controller to size the `NSPanel` to its content (see `TrayLayoutPolicy`).
@MainActor
@Observable
final class TrayLayoutModel {
    private(set) var rootHeight: Double = 0
    private(set) var viewportHeight: Double = 0
    private(set) var contentHeight: Double = 0

    // Writes only on a real change: every assignment notifies observers, and the panel
    // controller re-measures on each notification.
    func setRootHeight(_ value: Double) { if abs(value - rootHeight) > 0.25 { rootHeight = value } }
    func setViewportHeight(_ value: Double) { if abs(value - viewportHeight) > 0.25 { viewportHeight = value } }
    func setContentHeight(_ value: Double) { if abs(value - contentHeight) > 0.25 { contentHeight = value } }

    var hasMeasurement: Bool { rootHeight > 0 && contentHeight > 0 }

    func desiredHeight(screenHeight: Double) -> Double? {
        guard hasMeasurement else { return nil }
        return TrayLayoutPolicy.desiredHeight(
            rootHeight: rootHeight,
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            screenHeight: screenHeight
        )
    }
}
