import SwiftUI
import DayBarCore

/// Kanban card: status ring + title + priority flag on top, metadata chips below.
/// Hairline border instead of a drop shadow; hover and selection are border/fill changes.
struct TaskCardView<MenuContent: View>: View {
    let configuration: TaskRowConfiguration
    let actions: TaskRowActions
    @ViewBuilder var menu: () -> MenuContent

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeMetrics.spacingS) {
            HStack(alignment: .top, spacing: ThemeMetrics.spacingS) {
                StatusToggle(
                    status: configuration.status,
                    onToggleComplete: actions.toggleComplete,
                    onToggleInProgress: actions.toggleInProgress
                )
                .padding(.top, -3)
                .padding(.leading, -4)

                Text(configuration.title)
                    .font(ThemeTypography.cardTitle)
                    .fontWeight(configuration.status == .inProgress ? .medium : .regular)
                    .strikethrough(configuration.status == .done)
                    .foregroundStyle(configuration.status == .done ? .secondary : .primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PriorityFlag(priority: configuration.priority, rowHovered: hovering, onSet: actions.setPriority)
                    .padding(.top, -3)
                    .padding(.trailing, -4)
            }

            if hasMetadata {
                HStack(spacing: ThemeMetrics.spacingS) {
                    if let name = configuration.projectName {
                        Chip(text: name, systemImage: configuration.projectSymbol)
                    }
                    if let date = configuration.dateLabel, configuration.status != .done {
                        Chip(text: date)
                    }
                    if let age = configuration.ageLabel {
                        AgePill(text: age, tier: configuration.ageTier)
                    }
                    if configuration.hasNotes {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Has notes")
                    }
                    if let checklist = configuration.checklist, !checklist.isEmpty {
                        Label("\(checklist.done)/\(checklist.total)", systemImage: "checklist")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, ThemeMetrics.statusHitSize - 4 + ThemeMetrics.spacingS)
            }
        }
        .padding(ThemeMetrics.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: ThemeMetrics.cardRadius, style: .continuous)
                .fill(ThemeColors.cardFill)
            if hovering {
                RoundedRectangle(cornerRadius: ThemeMetrics.cardRadius, style: .continuous)
                    .fill(ThemeColors.cardHover)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: ThemeMetrics.cardRadius, style: .continuous)
                .strokeBorder(
                    configuration.isSelected ? Color.accentColor : ThemeColors.hairline(contrast),
                    lineWidth: configuration.isSelected ? 1.5 : ThemeMetrics.hairlineWidth
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: ThemeMetrics.cardRadius, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { actions.openDetails?() }
        .contextMenu { menu() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open details") { actions.openDetails?() }
    }

    private var hasMetadata: Bool {
        configuration.projectName != nil
            || (configuration.dateLabel != nil && configuration.status != .done)
            || configuration.ageLabel != nil
            || configuration.hasNotes
            || !(configuration.checklist?.isEmpty ?? true)
    }
}
