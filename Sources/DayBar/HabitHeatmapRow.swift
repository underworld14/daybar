import SwiftUI
import DayBarCore

/// One habit row with a 28-day consistency grid (GitHub-style).
struct HabitHeatmapRow: View {
    let title: String
    let cells: [HabitHeatmapCell]
    let currentStreak: Int

    private let cellSize: CGFloat = 8
    private let cellSpacing: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                if currentStreak > 0 {
                    Text("\(currentStreak)d")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: cellSpacing) {
                ForEach(cells) { cell in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: cell))
                        .frame(width: cellSize, height: cellSize)
                }
            }
        }
    }

    private func color(for cell: HabitHeatmapCell) -> Color {
        guard let status = cell.status else {
            return Color.secondary.opacity(0.08)
        }
        switch status {
        case .completed:
            return Color.green.opacity(0.75)
        case .skipped:
            return Color.secondary.opacity(0.25)
        case .pending:
            if Calendar.current.isDateInToday(cell.date) {
                return Color.secondary.opacity(0.18)
            }
            return cell.usedGrace
                ? Color.green.opacity(0.35)
                : Color.secondary.opacity(0.25)
        }
    }
}