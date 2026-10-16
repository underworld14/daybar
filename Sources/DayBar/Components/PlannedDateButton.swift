import SwiftUI
import DayBarCore

/// A task's planned day as a chip ("Tomorrow, Fri 17 Oct"); click to pick another day.
/// Overdue days use the aging color.
struct PlannedDateButton: View {
    let date: Date
    let calendar: Calendar
    var onPick: (Date) -> Void

    @State private var presenting = false

    var body: some View {
        let label = DayLabel.long(date, now: .now, calendar: calendar)
        Button {
            presenting.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: label.isOverdue ? "calendar.badge.exclamationmark" : "calendar")
                Text(label.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, ThemeMetrics.spacingM)
            .padding(.vertical, 4)
            .background(Capsule().fill(label.isOverdue ? ThemeColors.aging.opacity(0.16) : ThemeColors.chipFill))
            .foregroundStyle(label.isOverdue ? ThemeColors.aging : .primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Change the planned day")
        .accessibilityLabel("Planned for \(label.text)")
        .accessibilityHint("Opens a calendar")
        .popover(isPresented: $presenting, arrowEdge: .bottom) {
            PlannedDatePopover(selected: date, calendar: calendar) { picked in
                presenting = false
                onPick(picked)
            }
        }
    }
}
