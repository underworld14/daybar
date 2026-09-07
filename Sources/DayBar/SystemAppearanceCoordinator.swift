import AppKit
import DayBarCore

/// Keeps the AppKit panel hierarchy synchronized with the current macOS appearance.
/// SwiftUI content and sheets inherit from the panel, so no view-level scheme override
/// is needed and in-progress view state remains untouched during a theme change.
@MainActor
final class SystemAppearanceCoordinator {
    private weak var panel: NSPanel?
    private var observation: NSKeyValueObservation?

    func start(panel: NSPanel) {
        self.panel = panel
        panel.appearanceSource = NSApp
        observation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) {
            [weak self] application, change in
            let appearance = change.newValue ?? application.effectiveAppearance
            Task { @MainActor [weak self] in
                self?.apply(appearance)
            }
        }
    }

    func refresh() {
        apply(NSApp.effectiveAppearance)
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        panel = nil
    }

    private func apply(_ systemAppearance: NSAppearance) {
        guard let panel else { return }
        let appearance = SystemAppearancePolicy.resolvedAppearance(for: systemAppearance)
        apply(appearance, to: panel)
        panel.sheets.forEach { apply(appearance, to: $0) }
    }

    private func apply(_ appearance: NSAppearance, to window: NSWindow) {
        window.appearance = appearance
        window.contentView?.appearance = appearance
        window.contentView?.needsDisplay = true
    }
}
