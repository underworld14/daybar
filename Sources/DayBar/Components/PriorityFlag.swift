import SwiftUI
import DayBarCore

/// Interactive priority glyph: click cycles none → low → medium → high, right-click picks
/// a level directly, VoiceOver adjusts with increment/decrement. Invisible at `none` until
/// the row is hovered.
struct PriorityFlag: View {
    let priority: Priority
    var rowHovered = false
    var onSet: (Priority) -> Void

    var body: some View {
        Button {
            onSet(priority.next)
        } label: {
            PriorityGlyph(priority: priority, showsEmpty: rowHovered)
                .padding(.horizontal, 4)
                .frame(height: ThemeMetrics.statusHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Priority: \(priority.displayName). Click to change, or press 0–3.")
        .contextMenu {
            ForEach([Priority.high, .medium, .low, .none], id: \.self) { level in
                Button {
                    onSet(level)
                } label: {
                    if level == priority {
                        Label(level.displayName, systemImage: "checkmark")
                    } else {
                        Text(level.displayName)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Priority")
        .accessibilityValue(priority.displayName)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSet(priority.higher)
            case .decrement: onSet(priority.lower)
            @unknown default: break
            }
        }
    }
}
