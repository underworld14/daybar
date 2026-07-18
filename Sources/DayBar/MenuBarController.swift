import AppKit
import SwiftUI
import Observation
import UserNotifications
import KeyboardShortcuts
import DayBarCore

/// A floating panel that can take key focus, so the quick-add `TextField` works.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Clicks on a nonactivating panel don't always promote it to key — without that,
    /// SwiftUI `TextField` can report focus while AppKit never draws the insertion point.
    override func mouseDown(with event: NSEvent) {
        if !isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            makeKey()
        }
        super.mouseDown(with: event)
    }
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
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var appState: AppState!
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var gardenWindowController: GardenWindowController?
    private var outsideClickMonitor: Any?
    private let panelWidth: CGFloat = 360

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState = AppState(store: DataStore())
        appState.notifications.onAuthorizationGranted = { [weak self] in self?.appState.refresh() }
        UNUserNotificationCenter.current().delegate = self
        appState.notifications.requestAuthorization()
        setupStatusItem()
        setupPanel()
        trackGardenWindowRequests()
        Task { await appState.restoreRadioSession() }
        KeyboardShortcuts.onKeyDown(for: .quickAdd) { [weak self] in
            MainActor.assumeIsolated { self?.revealForQuickAdd() }
        }
        UpdateController.shared.start()
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Keep the panel up while a sheet (Settings/Stats/History/Review) is presented —
        // resigning for the sheet would otherwise tear it down mid-edit.
        guard !appState.isPanelSheetPresented, !appState.presentEndOfDayReview else { return }
        hidePanel()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel)
        button.imagePosition = .imageLeading
        // Monospaced digits so the live mm:ss countdown doesn't jitter the bar width.
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        updateStatusItem()
        trackStatusUpdates()
    }

    /// Reflect Pomodoro / overdue state in the menu-bar button: a live mm:ss countdown next to
    /// the timer glyph while a phase runs, otherwise the app glyph with an amber overdue count.
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let pomo = appState.pomodoro

        let symbol: String
        if pomo.isRunning {
            symbol = pomo.phase.isBreak ? "cup.and.saucer.fill" : "timer"
        } else if pomo.phase.isBreak {
            // Armed break waiting for play — distinct from fully idle.
            symbol = "cup.and.saucer"
        } else if appState.radio.isPlaying {
            symbol = "waveform"
        } else {
            symbol = "checklist"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "DayBar")
        image?.isTemplate = true
        button.image = image

        if pomo.isRunning {
            button.title = " " + pomo.remainingString
        } else if pomo.phase.isBreak {
            button.title = " break"
        } else if appState.overdueCount > 0 {
            button.title = " \(appState.overdueCount)"
        } else if appState.radio.isPlaying {
            button.title = " ♪"
        } else {
            button.title = ""
        }
    }

    /// Refresh the button whenever the timer ticks or the overdue count changes — reusing the
    /// engine's existing 1-second tick (no extra timer). Self-re-arms after each change.
    private func trackStatusUpdates() {
        withObservationTracking {
            _ = appState.pomodoro.phase
            _ = appState.pomodoro.remaining
            _ = appState.pomodoro.isRunning
            _ = appState.overdueCount
            _ = appState.radio.isPlaying
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStatusItem()
                self?.trackStatusUpdates()
            }
        }
    }

    // MARK: - Panel

    private func setupPanel() {
        let hosting = NSHostingView(rootView: TodayView().environment(appState))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        let contentSize = NSSize(width: panelWidth, height: desiredPanelHeight())

        // Frosted, rounded background so the panel reads like a native menu-bar popover
        // (the panel itself is clear; this view provides the material + corner radius).
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentSize))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMaskImage(cornerRadius: 12)
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
        // This panel's primary job is quick-add typing — stay key once shown.
        panel.becomesKeyOnlyIfNeeded = false
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
        trackPanelHeightUpdates()
    }

    /// Resize the open panel when habit/task counts change so adding/removing rows
    /// doesn't force a ScrollView until the next remount. Self-re-arms like `trackStatusUpdates()`.
    private func trackPanelHeightUpdates() {
        withObservationTracking {
            _ = appState.totalHabitsTodayCount
            _ = appState.totalTodayCount
            _ = appState.tomorrowTodos.count
            _ = appState.carriedTodos.count
            _ = appState.gardenSnapshot        // garden readiness toggles the Today summary
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updatePanelHeightIfNeeded()
                self?.trackPanelHeightUpdates()
            }
        }
    }

    // MARK: - Garden window

    /// Observe `openGardenWindowSignal` and open (or focus) the pop-out Garden window. Kept separate
    /// from the height tracker so open requests don't run panel-height math. Self-re-arms.
    private func trackGardenWindowRequests() {
        withObservationTracking {
            _ = appState.openGardenWindowSignal
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.openGardenWindow()
                self?.trackGardenWindowRequests()
            }
        }
    }

    private func openGardenWindow() {
        if let controller = gardenWindowController {
            NSApp.activate(ignoringOtherApps: true)
            controller.showAndFocus()
            return
        }
        // A real resizable window wants a Dock tile + Cmd-Tab; revert to accessory on close.
        NSApp.setActivationPolicy(.regular)
        let controller = GardenWindowController(appState: appState) { [weak self] in
            self?.gardenWindowDidClose()
        }
        gardenWindowController = controller
        appState.isGardenWindowOpen = true
        hidePanel()   // the panel's job is done; the window is the home of the full garden
        NSApp.activate(ignoringOtherApps: true)
        controller.showAndFocus()
    }

    private func gardenWindowDidClose() {
        appState.isGardenWindowOpen = false
        gardenWindowController = nil
        NSApp.setActivationPolicy(.accessory)
    }

    /// Apply `desiredPanelHeight()` only while the panel is visible (no thrash when hidden).
    private func updatePanelHeightIfNeeded() {
        guard panel.isVisible else { return }
        let height = desiredPanelHeight()
        guard abs(panel.frame.height - height) > 0.5 else { return }
        panel.setContentSize(NSSize(width: panelWidth, height: height))
        positionPanel()
    }

    /// A stretchable rounded-rect mask so the visual-effect view rounds cleanly — avoids the
    /// white corner artifacts that `layer.cornerRadius` leaves on an NSVisualEffectView.
    private static func roundedMaskImage(cornerRadius r: CGFloat) -> NSImage {
        let edge = r * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }

    /// Panel height sized to the current habit/task counts so a handful of rows don't force a
    /// scroll; capped to 80% of the screen, then the list scrolls.
    private func desiredPanelHeight() -> CGFloat {
        let screenHeight = (statusItem?.button?.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let cap = screenHeight * 0.8

        // Header + quick-add + garden summary + dividers + radio + pomodoro + padding.
        var chrome: CGFloat = 258
        if appState.totalTodayCount > 0 { chrome += 28 } // stacked tasks progress bar + legend
        if appState.gardenSnapshot == nil { chrome -= 44 } // no compact summary until the garden settles
        let rowHeight: CGFloat = 34   // habits may include a cue subtitle
        let sectionHeader: CGFloat = 24
        var rows: CGFloat = 0
        if appState.totalHabitsTodayCount > 0 {
            rows += sectionHeader + CGFloat(appState.totalHabitsTodayCount) * rowHeight
        } else {
            rows += sectionHeader + rowHeight // empty-state line
        }
        rows += sectionHeader + CGFloat(max(appState.totalTodayCount, 1)) * rowHeight
        if !appState.tomorrowTodos.isEmpty {
            rows += sectionHeader + CGFloat(appState.tomorrowTodos.count) * rowHeight
        }
        if !appState.carriedTodos.isEmpty {
            rows += sectionHeader + CGFloat(appState.carriedTodos.count) * rowHeight
        }
        return min(max(chrome + rows, 280), cap)
    }

    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    /// Open the panel (if needed) and focus the quick-add field — used by the global hotkey.
    private func revealForQuickAdd() {
        if panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            showPanel()
        }
        appState.quickAddFocusSignal += 1
    }

    private func showPanel() {
        appState.refresh()
        appState.quickAddFocusSignal += 1
        panel.setContentSize(NSSize(width: panelWidth, height: desiredPanelHeight()))
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
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
        let margin: CGFloat = 8
        let gapBelowButton: CGFloat = 8

        // Prefer centered under the status item, just below it.
        var x = buttonRect.midX - panelSize.width / 2
        var y = buttonRect.minY - panelSize.height - gapBelowButton

        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            // Keep fully inside the desktop area so the top isn't clipped by the menu bar
            // / notch (common when the status item sits near the camera housing).
            x = min(max(x, visible.minX + margin), visible.maxX - panelSize.width - margin)
            let maxOriginY = visible.maxY - panelSize.height - margin
            let minOriginY = visible.minY + margin
            y = min(y, maxOriginY)
            y = max(y, minOriginY)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let id = notification.request.identifier
        Task { @MainActor in
            let options = NotificationScheduling.willPresentOptions(
                identifier: id,
                panelVisible: self.panel.isVisible,
                allowSound: Preferences.shouldPlayAudibleAlerts()
            )
            completionHandler(options)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        Task { @MainActor in
            self.showPanel()
            if id == NotificationScheduler.ID.evening {
                self.appState.presentEndOfDayReview = true
            }
            completionHandler()
        }
    }
}
