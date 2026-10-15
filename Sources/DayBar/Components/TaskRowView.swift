import SwiftUI
import DayBarCore

/// One task row shared by the tray and the board list: status ring, title (inline rename),
/// metadata chips, a hover-revealed start button, the priority flag, and an actions menu
/// that doubles as the context menu.
struct TaskRowView<MenuContent: View>: View {
    let configuration: TaskRowConfiguration
    let actions: TaskRowActions
    var showsMenuButton = true
    @ViewBuilder var menu: () -> MenuContent

    @State private var hovering = false
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: ThemeMetrics.spacingS) {
            StatusToggle(
                status: configuration.status,
                onToggleComplete: actions.toggleComplete,
                onToggleInProgress: actions.toggleInProgress
            )

            if isEditing {
                TextField("Task", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit(commitEdit)
                    .onExitCommand(perform: cancelEdit)
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused && isEditing { commitEdit() }
                    }
            } else {
                titleView
            }

            Spacer(minLength: ThemeMetrics.spacingXS)

            if !isEditing {
                trailing
            }
        }
        .padding(.vertical, ThemeMetrics.rowVerticalPadding)
        .padding(.horizontal, ThemeMetrics.rowHorizontalPadding)
        .background {
            RoundedRectangle(cornerRadius: ThemeMetrics.rowRadius, style: .continuous)
                .fill(rowFill)
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            hovering = isHovering
            actions.hoverChanged?(isHovering)
        }
        .contextMenu { menu() }
        .accessibilityElement(children: .contain)
    }

    private var rowFill: Color {
        if configuration.isSelected { return ThemeColors.rowSelected }
        return hovering ? ThemeColors.rowHover : .clear
    }

    private var titleView: some View {
        HStack(spacing: ThemeMetrics.spacingXS) {
            if configuration.isFromReminders {
                Image(systemName: "list.bullet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Synced from Apple Reminders")
            }
            Text(configuration.title)
                .font(ThemeTypography.rowTitle)
                .strikethrough(configuration.status == .done)
                .foregroundStyle(configuration.status == .done ? .secondary : .primary)
                .fontWeight(configuration.status == .inProgress ? .medium : .regular)
                .lineLimit(2)
        }
        .contentShape(Rectangle())
        .modifier(TitleInteractionModifier(
            interaction: configuration.titleInteraction,
            canRename: actions.rename != nil,
            onOpen: { actions.openDetails?() },
            onRename: beginEdit
        ))
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: ThemeMetrics.spacingS) {
            detailIndicator

            if let name = configuration.projectName {
                Chip(text: name, systemImage: configuration.projectSymbol)
            }
            if let date = configuration.dateLabel, configuration.status != .done {
                Chip(text: date)
                    .help("Planned for \(date)")
            }
            if let age = configuration.ageLabel {
                AgePill(text: age, tier: configuration.ageTier)
            }

            if hovering && configuration.status != .done {
                Button(action: actions.toggleInProgress) {
                    Image(systemName: configuration.status == .inProgress ? "pause.fill" : "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(configuration.status == .inProgress ? "Move back to to-do" : "Start")
                .accessibilityLabel(configuration.status == .inProgress ? "Stop task" : "Start task")
                .transition(.opacity)
            }

            PriorityFlag(priority: configuration.priority, rowHovered: hovering, onSet: actions.setPriority)

            if showsMenuButton {
                Menu {
                    menu()
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(hovering ? 1 : 0.35)
                .accessibilityLabel("Task actions")
                .help("Task actions")
            }
        }
        .themeAnimation(.reveal, value: hovering)
    }

    @ViewBuilder
    private var detailIndicator: some View {
        let checklist = configuration.checklist.flatMap { $0.isEmpty ? nil : $0 }
        if configuration.hasNotes || checklist != nil {
            Button {
                actions.openDetails?()
            } label: {
                HStack(spacing: 3) {
                    if configuration.hasNotes {
                        Image(systemName: "note.text")
                    }
                    if let checklist {
                        Text("\(checklist.done)/\(checklist.total)")
                            .font(.caption2.monospacedDigit())
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open task details")
            .accessibilityLabel("Open task details")
        }
    }

    private func beginEdit() {
        guard actions.rename != nil else { return }
        draft = configuration.title
        isEditing = true
        fieldFocused = true
    }

    private func commitEdit() {
        actions.rename?(draft)
        isEditing = false
        fieldFocused = false
    }

    private func cancelEdit() {
        isEditing = false
        fieldFocused = false
    }
}

/// Click-to-open (board) vs double-click-to-rename (tray) on the row title.
private struct TitleInteractionModifier: ViewModifier {
    let interaction: TaskRowConfiguration.TitleInteraction
    let canRename: Bool
    let onOpen: () -> Void
    let onRename: () -> Void

    func body(content: Content) -> some View {
        switch interaction {
        case .openDetailsOnClick:
            // Single click only: pairing it with a double-click recognizer would delay
            // every click by the double-click interval. Rename lives in details/Return.
            content.onTapGesture(perform: onOpen)
        case .renameOnDoubleClick:
            content
                .onTapGesture(count: 2, perform: onRename)
                .help(canRename ? "Double-click to rename" : "")
        }
    }
}
