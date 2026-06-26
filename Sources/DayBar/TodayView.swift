import SwiftUI
import DayBarCore

/// The menu-bar panel: quick-add, today's list, the carry-over backlog, and the Pomodoro
/// control strip. Multi-add quick-add (Return adds and keeps focus) is the morning ritual.
struct TodayView: View {
    @Environment(AppState.self) private var appState

    @State private var newTitle: String = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            quickAdd
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    todaySection
                    if !appState.carriedTodos.isEmpty {
                        carriedSection
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 360)
            Divider()
            PomodoroStrip(appState: appState)
            footer
        }
        .padding(12)
        .frame(width: 320)
        .onAppear {
            appState.refresh()
            DispatchQueue.main.async { addFocused = true }
        }
    }

    private var header: some View {
        HStack {
            Text("DayBar").font(.headline)
            Spacer()
            Text(Date.now, format: .dateTime.weekday(.wide).day().month())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
            TextField("Add a task for today…", text: $newTitle)
                .textFieldStyle(.plain)
                .focused($addFocused)
                .onSubmit(addCurrent)
            Button(action: addCurrent) {
                Image(systemName: "return")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Add task")
        }
    }

    private func addCurrent() {
        appState.addTodo(title: newTitle)
        newTitle = ""
        addFocused = true // keep the field hot for multi-add
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today").font(.subheadline).bold()
                Spacer()
                Text("\(appState.completedTodayCount)/\(appState.totalTodayCount) done")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if appState.todayTodos.isEmpty {
                Text("Nothing planned yet. What matters today?")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 2)
            } else {
                ForEach(appState.todayTodos) { todo in
                    TodoRow(appState: appState, todo: todo)
                }
            }
        }
    }

    private var carriedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Carried over").font(.subheadline).bold()
                Spacer()
                if appState.overdueCount > 0 {
                    Text("\(appState.overdueCount) aging")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            ForEach(appState.carriedTodos) { todo in
                TodoRow(appState: appState, todo: todo, showReschedule: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A single task row: checkbox, title, optional age pill, and an overflow menu of actions.
struct TodoRow: View {
    var appState: AppState
    let todo: DailyTodo
    var showReschedule: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                appState.toggleComplete(todo)
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .strikethrough(todo.isCompleted)
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .lineLimit(2)

            Spacer(minLength: 4)

            if let label = todo.ageLabel() {
                AgePill(text: label, tier: todo.escalationTier(thresholds: appState.thresholds))
            }

            Menu {
                if showReschedule {
                    Button("Bring to today") { appState.reschedule(todo) }
                }
                Button("Delay to tomorrow") { appState.delay(todo) }
                Button("Drop", role: .destructive) { appState.drop(todo) }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

/// Compact age pill. Grey for fresh slips, amber once aging — never red (gentle default).
struct AgePill: View {
    let text: String
    let tier: EscalationTier

    private var color: Color { tier >= .aging ? .orange : .secondary }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}

/// Pomodoro control strip. Live countdown via self-animating `Text(timerInterval:)`.
struct PomodoroStrip: View {
    var appState: AppState

    var body: some View {
        let pomo = appState.pomodoro
        HStack(spacing: 8) {
            Image(systemName: pomo.phase.isBreak ? "cup.and.saucer" : "timer")
                .foregroundStyle(.tint)
            Text(pomo.phase == .idle ? "Focus" : pomo.phase.displayName)
                .font(.subheadline)

            Spacer()

            if let end = pomo.endDate, pomo.isRunning, end > Date.now {
                Text(timerInterval: Date.now...end, countsDown: true)
                    .monospacedDigit()
                    .font(.subheadline.weight(.semibold))
            } else {
                Text(pomo.remainingString)
                    .monospacedDigit()
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Button {
                appState.togglePomodoro()
            } label: {
                Image(systemName: pomo.isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)

            Button {
                pomo.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}
