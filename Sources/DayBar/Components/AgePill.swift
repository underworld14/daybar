import SwiftUI
import DayBarCore

/// Compact age pill. Grey for fresh slips, amber once aging — never red (gentle default).
struct AgePill: View {
    let text: String
    let tier: EscalationTier

    private var color: Color { tier >= .aging ? .orange : .secondary }

    var body: some View {
        HStack(spacing: 2) {
            if tier >= .aging {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.18)))
        .foregroundStyle(color)
        .accessibilityLabel(tier >= .aging ? "Aging \(text)" : "Waiting \(text)")
    }
}
