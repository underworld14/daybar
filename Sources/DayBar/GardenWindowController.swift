import AppKit
import SwiftUI
import DayBarCore

/// The pop-out Garden window: a standard resizable window hosting the roaming farm (SwiftUI +
/// SpriteKit). Owned/retained by `AppDelegate`; it resets state via `onClose` when the user closes it.
@MainActor
final class GardenWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(appState: AppState, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Focus Garden"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.contentViewController = NSHostingController(
            rootView: FarmWindowRoot().environment(appState)
        )
        window.setFrameAutosaveName("DayBarGardenWindow")
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("DayBarGardenWindow") { window.center() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Bring the (already-created) window to the front — the dedupe path for a second open request.
    func showAndFocus() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
