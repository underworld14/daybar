import SwiftUI
import DayBarCore

/// Graphical date picker with quick presets, shared by the board composers.
struct ComposerDatePopover: View {
    let scope: TaskScope
    let calendar: Calendar
    @Binding var date: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker(
                "Planned for",
                selection: Binding(
                    get: { date ?? scopeDefault },
                    set: { date = $0 }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            HStack {
                Button("Today") { date = DayMath.startOfDay(.now, calendar: calendar) }
                Button("Tomorrow") { date = DayMath.nextDay(.now, calendar: calendar) }
                Spacer()
                Button("Clear") { date = nil }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 300)
    }

    private var scopeDefault: Date {
        scope == .tomorrow
            ? DayMath.nextDay(.now, calendar: calendar)
            : DayMath.startOfDay(.now, calendar: calendar)
    }
}
