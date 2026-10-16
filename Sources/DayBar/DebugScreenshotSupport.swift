#if DEBUG
import AppKit

/// Debug-only helpers for capturing marketing screenshots without touching the user's
/// system settings: `--appearance light|dark` forces this app's appearance, and
/// `--screenshot-backdrop` puts a plain neutral window right behind DayBar's windows so
/// their translucent materials don't pick up the wallpaper or other apps.
@MainActor
enum DebugScreenshotSupport {
    private static var backdrop: NSWindow?

    static func applyAppearanceOverride() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--appearance"), index + 1 < arguments.count else { return }
        switch arguments[index + 1] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    /// Shows (or re-stacks) the neutral backdrop directly below `window`, at its level.
    static func placeBackdrop(behind window: NSWindow) {
        guard CommandLine.arguments.contains("--screenshot-backdrop"),
              let screen = window.screen ?? NSScreen.main else { return }
        let backdrop = backdrop ?? makeBackdrop()
        self.backdrop = backdrop
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        backdrop.backgroundColor = isDark
            ? NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x20 / 255, alpha: 1)
            : NSColor(srgbRed: 0xEC / 255, green: 0xEC / 255, blue: 0xEE / 255, alpha: 1)
        backdrop.level = window.level
        backdrop.setFrame(screen.frame, display: true)
        backdrop.order(.below, relativeTo: window.windowNumber)
    }

    private static func makeBackdrop() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }
}
#endif
