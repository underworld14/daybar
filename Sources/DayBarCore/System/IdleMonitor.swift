import Foundation
import CoreGraphics

/// Reads system-wide keyboard/mouse idle time. The closure is swappable in tests.
public enum IdleMonitor {
    public static var secondsSinceLastInput: () -> TimeInterval = {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }
}
