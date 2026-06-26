import SwiftUI
import DayBarCore

/// The menu-bar panel: quick-add, today's list, the carry-over backlog, and the Pomodoro
/// control strip. Multi-add quick-add (Return adds and keeps focus) is the morning ritual.
struct TodayView: View {
    @Environment(AppState.self) private var appState

    @State private var newTitle = ""
    @FocusState private var addFocused: Bool
    @State private var showSettings = false

    private let wordmarkFont = Font.system(size: 15, weight: .bold, design: .rounded)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            quickAdd
            if appState.totalTodayCount > 0 { progressBar }
            Divider().padding(.top, 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    todaySection
                    if !appState.carriedTodos.isEmpty { carriedSection }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 360)
            Divider()
            PomodoroStrip(appState: appState)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            appState.refresh()
            DispatchQueue.main.async { addFocused = true }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("DayBar").font(wordmarkFont)
            Spacer()
            Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.caption)
                .foregroundStyle(.secondary)
            Menu {
                Button { showSettings = true } label: { Label("Settings…", systemImage: "gearshape") }
                Divider()
                Button("Quit DayBar") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: - Quick add

    private var trimmed: String { newTitle.trimmingCharacters(in: .whitespaces) }

    private var quickAdd: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
            TextField("Add a task for today…", text: $newTitle)
                .textFieldStyle(.plain)
                .focused($addFocused)
                .onSubmit(addCurrent)
            if !trimmed.isEmpty {
                Button(action: addCurrent) {
                    Image(systemName: "return").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add task")
            }
        }
    }

    private func addCurrent() {
        appState.addTodo(title: newTitle)
        newTitle = ""
        addFocused = true // keep the field hot for multi-add
    }

    private var progressBar: some View {
        ProgressView(value: Double(appState.completedTodayCount), total: Double(max(1, appState.totalTodayCount)))
            .progressViewStyle(.linear)
            .tint(.accentColor)
            .scaleEffect(x: 1, y: 0.6, anchor: .center)
    }

    // MARK: - Sections

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TODAY").font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
                Spacer()
                Text("\(appState.completedTodayCount)/\(appState.totalTodayCount)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if appState.todayTodos.isEmpty {
                Text("Nothing planned yet. What matters today?")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 2)
            } else {
                ForEach(appState.todayTodos) { TodoRow(appState: appState, todo: $0) }
            }
        }
    }

    private var carriedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CARRIED OVER").font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
                Spacer()
                if appState.overdueCount > 0 {
                    Text("\(appState.overdueCount) aging").font(.caption2).foregroundStyle(.orange)
                }
            }
            ForEach(appState.carriedTodos) { TodoRow(appState: appState, todo: $0, showReschedule: true) }
        }
    }
}

/// A single task row: checkbox, title, optional age pill, and a hover-revealed actions menu.
struct TodoRow: View {
    var appState: AppState
    let todo: DailyTodo
    var showReschedule = false

    @State private var hovering = false

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
                if showReschedule { Button("Bring to today") { appState.reschedule(todo) } }
                Button("Delay to tomorrow") { appState.delay(todo) }
                Button("Drop", role: .destructive) { appState.drop(todo) }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
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

    private let digitFont = Font.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit()

    var body: some View {
        let pomo = appState.pomodoro
        HStack(spacing: 8) {
            Image(systemName: pomo.phase.isBreak ? "cup.and.saucer" : "timer").foregroundStyle(.tint)
            Text(pomo.phase == .idle ? "Focus" : pomo.phase.displayName).font(.subheadline)

            Spacer()

            Group {
                if let end = pomo.endDate, pomo.isRunning, end > Date.now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                } else {
                    Text(pomo.remainingString).foregroundStyle(.secondary)
                }
            }
            .font(digitFont)

            Button { appState.togglePomodoro() } label: {
                Image(systemName: pomo.isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)

            Button { pomo.stop() } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}
