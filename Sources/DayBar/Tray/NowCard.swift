import SwiftUI
import DayBarCore

/// The tray's "Now" card: what's in progress, with focus bound to a task. Always mounted
/// (see `TraySectionPolicy.showsNowSection`); with nothing in progress it has no height.
struct NowCard: View {
    var appState: AppState
    var onOpenDetails: (DailyTodo) -> Void

    var body: some View {
        // Every in-progress task lives here (Today/Carried leave them out), so none are capped.
        let tasks = appState.nowTodos
        VStack(alignment: .leading, spacing: ThemeMetrics.spacingXS) {
            if !tasks.isEmpty {
                SectionHeader("Now") {
                    if tasks.count > 1 { Text("\(tasks.count)") }
                }
                ForEach(tasks) { todo in
                    NowRow(appState: appState, todo: todo, onOpenDetails: { onOpenDetails(todo) })
                        .id(todo.id)
                }
            }
        }
        .padding(.horizontal, tasks.isEmpty ? 0 : ThemeMetrics.spacingM)
        .padding(.vertical, tasks.isEmpty ? 0 : ThemeMetrics.spacingS)
        .background {
            if !tasks.isEmpty {
                RoundedRectangle(cornerRadius: ThemeMetrics.cardRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                RoundedRectangle(cornerRadius: ThemeMetrics.cardRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
            }
        }
        .themeAnimation(.reorder, value: tasks.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now")
    }
}

/// One in-progress task: ring (completes), title, and focus controls bound to it.
private struct NowRow: View {
    var appState: AppState
    let todo: DailyTodo
    var onOpenDetails: () -> Void

    @Environment(TrayInteractionModel.self) private var interaction: TrayInteractionModel?

    private let digitFont = Font.system(.callout, design: .rounded).weight(.semibold).monospacedDigit()

    var body: some View {
        let pomo = appState.pomodoro
        let isFocused = appState.focusTodoID == todo.id && pomo.phase == .work
        HStack(spacing: ThemeMetrics.spacingS) {
            StatusToggle(
                status: TaskStatus(todo),
                onToggleComplete: { withThemeAnimation(.reorder) { appState.toggleComplete(todo) } },
                onToggleInProgress: { withThemeAnimation(.reorder) { appState.toggleInProgress(todo) } }
            )
            .padding(.leading, -4)

            Text(todo.title)
                .fontWeight(.medium)
                .lineLimit(2)
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: onOpenDetails)

            Spacer(minLength: ThemeMetrics.spacingXS)

            if todo.pomodoroCount > 0 {
                Chip(text: "\(todo.pomodoroCount)", systemImage: "timer")
                    .help("\(todo.pomodoroCount) focus session\(todo.pomodoroCount == 1 ? "" : "s")")
            }

            if isFocused {
                Group {
                    if let end = pomo.endDate, pomo.isRunning, end > Date.now {
                        Text(timerInterval: Date.now...end, countsDown: true)
                    } else {
                        Text(pomo.remainingString).foregroundStyle(.secondary)
                    }
                }
                .font(digitFont)
                .foregroundStyle(.tint)

                Button { appState.togglePomodoro() } label: {
                    Image(systemName: pomo.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .help(pomo.isRunning ? "Pause focus" : "Resume focus")
                .accessibilityLabel(pomo.isRunning ? "Pause focus" : "Resume focus")

                Button { appState.stopPomodoro() } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Stop focus session")
                .accessibilityLabel("Stop focus session")
            } else {
                Button {
                    appState.startFocus(on: todo)
                } label: {
                    Label("Focus", systemImage: "timer")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Start a focus session on this task")
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background {
            if interaction?.selectedTodoID == todo.id {
                RoundedRectangle(cornerRadius: ThemeMetrics.rowRadius, style: .continuous)
                    .fill(ThemeColors.rowSelected)
            }
        }
        .padding(.horizontal, -4)
        .contentShape(Rectangle())
        .onHover { hovering in interaction?.hoverChanged(todo.id, hovering: hovering) }
        .contextMenu {
            Button("Focus on This") { appState.startFocus(on: todo) }
            Button("Complete") { appState.toggleComplete(todo) }
            Button("Move Back to To-Do") { appState.resetTodo(todo) }
            Button("Details…", action: onOpenDetails)
        }
    }
}
