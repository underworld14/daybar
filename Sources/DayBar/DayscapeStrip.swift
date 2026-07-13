import SwiftUI
import DayBarCore

/// Compact 7-day Dayscape strip + focus streak pill for the Today panel.
struct DayscapeStrip: View {
    let cells: [FocusDayCell]
    let currentStreak: Int
    let graceRemaining: Int

    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 4

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: cellSpacing) {
                ForEach(cells) { cell in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(fill(for: cell))
                        .frame(width: cellSize, height: cellSize)
                        .overlay {
                            if cell.usedGrace, cell.completedSessions == 0 {
                                Image(systemName: "circle")
                                    .font(.system(size: 6, weight: .semibold))
                                    .foregroundStyle(Color.indigo.opacity(0.55))
                            }
                        }
                        .accessibilityLabel(accessibilityLabel(for: cell))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dayscape, last \(cells.count) days")

            Spacer(minLength: 0)

            if currentStreak > 0 {
                Text("\(currentStreak)d")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .help(graceHelp)
                    .accessibilityLabel("Focus streak \(currentStreak) days")
                    .accessibilityHint(graceHelp)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var graceHelp: String {
        if graceRemaining > 0 {
            return "\(graceRemaining) grace day left this week"
        }
        return "No grace days left this week"
    }

    private func fill(for cell: FocusDayCell) -> Color {
        switch cell.fillLevel {
        case 0:
            return Color.secondary.opacity(0.12)
        case 1:
            return Color.indigo.opacity(0.35)
        case 2:
            return Color.indigo.opacity(0.55)
        default:
            return Color.indigo.opacity(0.8)
        }
    }

    private func accessibilityLabel(for cell: FocusDayCell) -> String {
        let day = cell.date.formatted(.dateTime.weekday(.abbreviated))
        if cell.completedSessions > 0 {
            let unit = cell.completedSessions == 1 ? "session" : "sessions"
            return "\(day), \(cell.completedSessions) \(unit)"
        }
        if cell.usedGrace {
            return "\(day), grace"
        }
        return "\(day), empty"
    }
}
