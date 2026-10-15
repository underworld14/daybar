import SwiftUI
import DayBarCore

/// The tray's quick-add: one field that understands `!`/`!!`/`!!!`, `besok`/`tmr`/`hari ini`
/// and `#project`, a day chip (Today ↔ Tomorrow) instead of a separate segmented control, and
/// live chips showing what the typed syntax will set.
struct QuickAddField: View {
    @Binding var text: String
    @Binding var addForTomorrow: Bool
    var focused: FocusState<Bool>.Binding
    let projects: [QuickAddParser.ProjectRef]
    var onSubmit: () -> Void
    var onActivate: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    private var parsed: QuickAddResult? { QuickAddParser.parse(text, projects: projects) }

    /// The day the task will land on: typed syntax wins over the chip.
    private var effectiveTomorrow: Bool {
        parsed?.day.map { $0 == .tomorrow } ?? addForTomorrow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.spacingS) {
            HStack(spacing: ThemeMetrics.spacingM) {
                Button(action: onActivate) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(focused.wrappedValue ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Focus quick-add")
                .accessibilityLabel("Focus quick-add")

                ZStack(alignment: .leading) {
                    TextField("Add a task…", text: $text)
                        .textFieldStyle(.plain)
                        .focused(focused)
                        .tint(.accentColor)
                        .onSubmit(onSubmit)
                        .accessibilityHint("Type !, !! or !!! for priority, besok or tmr for tomorrow, # for a project")

                    // Borderless nonactivating panels often omit AppKit's insertion point
                    // even when FocusState is true — draw one while the field is empty.
                    if focused.wrappedValue && text.isEmpty {
                        BlinkingInsertionCaret()
                            .padding(.leading, 1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }

                dayChip

                if parsed != nil {
                    Button(action: onSubmit) {
                        Image(systemName: "return").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Add task")
                    .accessibilityLabel("Add task")
                }
            }
            .padding(.horizontal, ThemeMetrics.spacingM)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture(perform: onActivate)
            .background {
                RoundedRectangle(cornerRadius: ThemeMetrics.fieldRadius, style: .continuous)
                    .fill(focused.wrappedValue ? ThemeColors.fieldFillFocused : ThemeColors.fieldFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: ThemeMetrics.fieldRadius, style: .continuous)
                    .strokeBorder(
                        focused.wrappedValue ? Color.accentColor : ThemeColors.hairline(contrast),
                        lineWidth: focused.wrappedValue ? 1.5 : 1
                    )
            }
            .themeAnimation(.reveal, value: focused.wrappedValue)

            if let tokens = parsed?.tokens, !tokens.isEmpty {
                tokenChips(tokens)
                    .transition(.opacity)
            }
        }
        .themeAnimation(.reveal, value: parsed?.tokens.isEmpty ?? true)
    }

    /// Today/Tomorrow toggle. Shows the typed day (tinted) when the syntax overrides it.
    private var dayChip: some View {
        let overridden = parsed?.day != nil
        return Button {
            addForTomorrow.toggle()
        } label: {
            Text(effectiveTomorrow ? "Tomorrow" : "Today")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(overridden ? Color.accentColor.opacity(0.18) : ThemeColors.chipFill))
                .foregroundStyle(overridden ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(overridden)
        .help(overridden ? "Set by what you typed" : "Click to switch between today and tomorrow")
        .accessibilityLabel("Plan for \(effectiveTomorrow ? "tomorrow" : "today")")
    }

    private func tokenChips(_ tokens: [QuickAddToken]) -> some View {
        HStack(spacing: ThemeMetrics.spacingS) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                switch token.kind {
                case .priority(let priority):
                    HStack(spacing: 4) {
                        PriorityGlyph(priority: priority)
                        Text(priority.displayName)
                    }
                    .font(ThemeTypography.chip)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(ThemeColors.chipFill))
                    .foregroundStyle(.secondary)
                case .day(let day):
                    Chip(text: day == .tomorrow ? "Tomorrow" : "Today", systemImage: "calendar")
                case .project(_, let name):
                    Chip(text: name, systemImage: "folder")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 26)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Will set: " + tokens.map(\.source).joined(separator: ", "))
    }
}
