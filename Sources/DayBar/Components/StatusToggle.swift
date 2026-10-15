import AppKit
import SwiftUI

/// The task status ring. Click completes (or un-completes) in one step; ⌥-click toggles
/// "in progress". Hovering an open task previews the checkmark so the click is predictable.
struct StatusToggle: View {
    let status: TaskStatus
    var onToggleComplete: () -> Void
    var onToggleInProgress: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: handleClick) {
            ring
                .frame(width: ThemeMetrics.statusHitSize, height: ThemeMetrics.statusHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
        .accessibilityLabel(status == .done ? "Mark incomplete" : "Mark complete")
        .accessibilityValue(status.accessibilityValue)
        .accessibilityAction(named: status == .inProgress ? "Stop" : "Start") { onToggleInProgress() }
    }

    private var ring: some View {
        let size = ThemeMetrics.statusRingSize
        return ZStack {
            switch status {
            case .done:
                Circle().fill(ThemeColors.statusDone)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            case .inProgress:
                Circle().strokeBorder(ThemeColors.statusProgress, lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: 0.5)
                    .fill(ThemeColors.statusProgress)
                    .rotationEffect(.degrees(90))
                    .padding(3)
            case .toDo:
                Circle().strokeBorder(
                    hovering ? ThemeColors.statusDone : ThemeColors.statusTodo.opacity(contrast == .increased ? 1 : 0.7),
                    lineWidth: 1.5
                )
                if hovering {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(ThemeColors.statusDone.opacity(0.75))
                }
            }
        }
        .frame(width: size, height: size)
        .themeAnimation(.snap, value: status)
    }

    private func handleClick() {
        if NSEvent.modifierFlags.contains(.option) {
            onToggleInProgress()
        } else {
            onToggleComplete()
        }
    }

    private var helpText: String {
        switch status {
        case .toDo: return "Complete (⌥-click to start)"
        case .inProgress: return "Complete (⌥-click to stop)"
        case .done: return "Mark incomplete"
        }
    }
}
