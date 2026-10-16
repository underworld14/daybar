import SwiftUI
import DayBarCore

/// Date picking in one click: presets (Today, Tomorrow, This weekend, Next week) above a
/// month calendar. Past days are disabled. Picking anything commits and closes.
struct PlannedDatePopover: View {
    let selected: Date?
    let calendar: Calendar
    var onPick: (Date) -> Void
    /// Composer only: drop the custom date and fall back to the view's day.
    var onClear: (() -> Void)?

    @State private var month: Date
    private let today: Date

    init(selected: Date?, calendar: Calendar, onPick: @escaping (Date) -> Void, onClear: (() -> Void)? = nil) {
        self.selected = selected
        self.calendar = calendar
        self.onPick = onPick
        self.onClear = onClear
        let today = DayMath.startOfDay(.now, calendar: calendar)
        self.today = today
        // An overdue date can't be picked again, so open on the current month instead.
        let anchor = selected.map { max(DayMath.startOfDay($0, calendar: calendar), today) } ?? today
        _month = State(initialValue: MonthGrid.monthStart(anchor, calendar: calendar))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.spacingM) {
            presets
            Divider()
            monthHeader
            weekdayRow
            grid
            if let onClear {
                Divider()
                Button("Clear Date", action: onClear)
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
        }
        .padding(ThemeMetrics.spacingL)
        .frame(width: 268)
    }

    // MARK: Presets

    private var presets: some View {
        VStack(spacing: 2) {
            ForEach(QuickDatePresets.presets(now: today, calendar: calendar)) { preset in
                PresetRow(
                    title: preset.title,
                    detail: shortDate(preset.date),
                    isSelected: isSelected(preset.date),
                    action: { onPick(preset.date) }
                )
            }
        }
    }

    // MARK: Month

    private var monthHeader: some View {
        HStack {
            Text(monthTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                month = MonthGrid.shift(month, by: -1, calendar: calendar)
            } label: {
                Image(systemName: "chevron.left").frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(month <= MonthGrid.monthStart(today, calendar: calendar))
            .accessibilityLabel("Previous month")
            Button {
                month = MonthGrid.shift(month, by: 1, calendar: calendar)
            } label: {
                Image(systemName: "chevron.right").frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Next month")
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(MonthGrid.weekdaySymbols(calendar: calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
            ForEach(MonthGrid.days(for: month, today: today, calendar: calendar)) { day in
                DayCell(
                    day: day,
                    isSelected: isSelected(day.date),
                    accessibilityName: DayLabel.long(day.date, now: today, calendar: calendar).text,
                    action: { onPick(day.date) }
                )
            }
        }
    }

    // MARK: Helpers

    private func isSelected(_ date: Date) -> Bool {
        guard let selected else { return false }
        return DayMath.startOfDay(selected, calendar: calendar) == date
    }

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return fmt.string(from: month)
    }

    private func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.timeZone = calendar.timeZone
        fmt.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return fmt.string(from: date)
    }
}

/// A preset line: name on the left, its date on the right.
private struct PresetRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(detail).foregroundStyle(.secondary)
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.tint).font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, ThemeMetrics.spacingS)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: ThemeMetrics.rowRadius, style: .continuous)
                    .fill(hovering ? ThemeColors.rowHover : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One calendar day: accent fill when selected, a ring for today, disabled when past.
private struct DayCell: View {
    let day: MonthGridDay
    let isSelected: Bool
    let accessibilityName: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("\(day.dayNumber)")
                .font(.callout.monospacedDigit())
                .fontWeight(day.isToday ? .semibold : .regular)
                .frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(foreground)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor)
                    } else if hovering && !day.isPast {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ThemeColors.rowHover)
                    }
                }
                .overlay {
                    if day.isToday && !isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day.isPast)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        if isSelected { return .white }
        if day.isPast { return Color.secondary.opacity(0.45) }
        return day.isInMonth ? .primary : .secondary
    }
}
