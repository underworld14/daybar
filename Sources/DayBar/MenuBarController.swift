import AppKit
import SwiftUI
import DayBarCore

/// A floating panel that can take key focus, so the quick-add `TextField` works.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// `NSHostingView` that ignores mouse events so clicks fall through to the status button.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Drives the menu-bar surface with AppKit (`NSStatusItem` + `NSPanel` hosting SwiftUI)
/// instead of SwiftUI's `MenuBarExtra`, whose `.window` content does not reliably re-render
/// on `@Observable` changes (macOS 26 — verified: state updated, view stayed stale). The
/// panel is a real key window, so `TextField` focus, `onSubmit`, and SwiftUI re-rendering all
/// behave normally.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState = AppState(store: DataStore())
        setupStatusItem()
        setupPanel()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel)

        let label = PassthroughHostingView(rootView: MenuBarLabel(appState: appState))
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -6),
        ])
    }

    // MARK: - Panel

    private func setupPanel() {
        let hosting = NSHostingView(rootView: TodayView().environment(appState))
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let contentSize = NSSize(width: max(320, fitting.width), height: max(220, fitting.height))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // Frosted, rounded background so the panel reads like a native menu-bar popover
        // (the panel itself is clear; this view provides the material + corner radius).
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentSize))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = effect
    }

    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    private func showPanel() {
        appState.refresh()
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }

    private func hidePanel() {
        panel.orderOut(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func positionPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let inWindow = button.convert(button.bounds, to: nil)
        let buttonRect = buttonWindow.convertToScreen(inWindow)
        let panelSize = panel.frame.size
        var x = buttonRect.midX - panelSize.width / 2
        let y = buttonRect.minY - panelSize.height - 4
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let maxX = screen.visibleFrame.maxX - panelSize.width - 8
            let minX = screen.visibleFrame.minX + 8
            x = min(max(x, minX), maxX)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
