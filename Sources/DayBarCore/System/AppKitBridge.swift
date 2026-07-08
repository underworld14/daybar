#if canImport(AppKit)
import AppKit

/// Containment point for the few unavoidable AppKit touchpoints. Keeping these here
/// means a future swap to `NSStatusItem + NSPanel` (if `MenuBarExtra` ever regresses)
/// is isolated to one file.
@MainActor
public enum AppKitBridge {
    /// Hide the Dock icon / Cmd-Tab entry (accessory app). Works without an Info.plist.
    public static func setAccessoryActivationPolicy() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    /// Bring the app forward so a panel `TextField` can take keyboard focus. An accessory
    /// app's menu-bar window is non-activating, so quick-add must request activation.
    public static func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Best-effort: make the menu-bar panel window key so text entry works immediately.
    public static func makeMenuBarWindowKey() {
        activateApp()
        // The MenuBarExtra window is the visible, non-main window owned by the app.
        if let window = NSApplication.shared.windows.first(where: { $0.isVisible && !$0.isMainWindow }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    public static func playPhaseEndSound(named name: String = "Glass") {
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    /// Deep-links into System Settings > Apple Intelligence & Siri. Private pane
    /// identifier (no public API exists for this), so this is best-effort: if the URL
    /// scheme ever changes, it silently no-ops instead of crashing.
    public static func openAppleIntelligenceSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
