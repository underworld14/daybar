#if canImport(AppKit)
import AppKit

/// Containment point for the few unavoidable AppKit touchpoints. Keeping these here
/// means a future swap to `NSStatusItem + NSPanel` (if `MenuBarExtra` ever regresses)
/// is isolated to one file.
@MainActor
public enum AppKitBridge {
    /// Deep-links into System Settings > Apple Intelligence & Siri. Private pane
    /// identifier (no public API exists for this), so this is best-effort: if the URL
    /// scheme ever changes, it silently no-ops instead of crashing.
    public static func openAppleIntelligenceSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Deep-links into System Settings > Notifications > DayBar. Same private-pane caveat
    /// as `openAppleIntelligenceSettings`: best-effort, no-ops if the scheme ever changes.
    public static func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
