import SwiftUI
import DayBarCore

/// The menu-bar panel: quick-add, today's list, the carry-over backlog, and the Pomodoro
/// control strip. Multi-add quick-add (Return adds and keeps focus) is the morning ritual.
struct TodayView: View {
    @Environment(AppState.self) private var appState

    @State private var newTitle = ""
    @FocusState private var addFocused: Bool
    @State private var showSettings = false
    @State private var showStats = false

    private let wordmarkFont = Font.system(size: 15, weight: .bold, design: .rounded)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            quickAdd
            if appState.totalTodayCount > 0 { progressBar }
            if let milestone = appState.habitMilestoneMessage {
                Text(milestone)
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .padding(.vertical, 2)
            }
            Divider().padding(.top, 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    habitsSection
                    todaySection
                    if !appState.carriedTodos.isEmpty { carriedSection }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)
            Divider()
            PomodoroStrip(appState: appState)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            appState.refresh()
            DispatchQueue.main.async { addFocused = true }
        }
        .onChange(of: appState.quickAddFocusSignal) { _, _ in addFocused = true }
        .onChange(of: appState.habitMilestoneMessage) { _, message in
            guard let message else { return }
            Task {
                try? await Task.sleep(for: .seconds(3))
                if appState.habitMilestoneMessage == message {
                    appState.habitMilestoneMessage = nil
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState)
        }
        .sheet(isPresented: $showStats) {
            AnalyticsView(appState: appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.presentEndOfDayReview },
            set: { appState.presentEndOfDayReview = $0 }
        )) {
            EndOfDayReviewView(appState: appState)
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
                Button { showStats = true } label: { Label("Statistics…", systemImage: "chart.bar") }
                Button { appState.presentEndOfDayReview = true } label: { Label("Review day…", systemImage: "checkmark.circle") }
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
        StackedTodoProgressBar(
            done: appState.completedTodayCount,
            inProgress: appState.inProgressTodayCount,
            total: appState.totalTodayCount
        )
    }

    // MARK: - Sections

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("HABITS").font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
                Spacer()
                if appState.totalHabitsTodayCount > 0 {
                    Text("\(appState.completedHabitsTodayCount)/\(appState.totalHabitsTodayCount)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if appState.todayHabits.isEmpty {
                Text("No habits yet — add one in Settings.")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 2)
            } else {
                ForEach(appState.todayHabits) { habit in
                    HabitRow(appState: appState, habit: habit)
                        .id("\(habit.log.id)-\(habit.log.statusRaw)")
                }
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TODAY").font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
                Spacer()
                todoProgressLabel
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if appState.todayTodos.isEmpty {
                Text("Nothing planned yet. What matters today?")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 2)
            } else {
                ForEach(appState.todayTodos) { todo in
                    TodoRow(appState: appState, todo: todo)
                        .id("\(todo.id)-\(todo.statusRaw)-\(todo.completedDate?.timeIntervalSince1970 ?? 0)")
                }
            }
        }
    }

    private var todoProgressLabel: Text {
        let done = appState.completedTodayCount
        let active = appState.inProgressTodayCount
        let total = appState.totalTodayCount
        if active > 0 {
            return Text("\(done) done · \(active) active · \(total)")
        }
        return Text("\(done)/\(total)")
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

/// A single habit row: checkbox, title, cue, and streak pill.
struct HabitRow: View {
    var appState: AppState
    let habit: TodayHabit

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button { appState.toggleHabit(habit.log) } label: {
                Image(systemName: habit.log.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(habit.log.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(habit.template.title)
                    .strikethrough(habit.log.isCompleted)
                    .foregroundStyle(habit.log.isCompleted ? .secondary : .primary)
                    .lineLimit(1)
                if !habit.template.cueText.isEmpty {
                    Text(habit.template.cueText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if habit.currentStreak > 0 {
                Text("\(habit.currentStreak)d")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                    .foregroundStyle(.green)
                    .help(habit.graceRemaining > 0 ? "\(habit.graceRemaining) grace day left this week" : "No grace days left this week")
            }

            Menu {
                if habit.log.isCompleted || habit.log.status == .skipped {
                    Button("Mark incomplete") { appState.toggleHabit(habit.log) }
                } else {
                    Button("Skip today") { appState.skipHabit(habit.log) }
                }
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

/// A single task row: checkbox, title (double-click to rename), optional age pill, and a
/// hover-revealed actions menu.
struct TodoRow: View {
    var appState: AppState
    let todo: DailyTodo
    var showReschedule = false

    @State private var hovering = false
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                appState.advanceTodo(todo)
            } label: {
                Image(systemName: todoStatusIcon)
                    .foregroundStyle(todoStatusColor)
            }
            .buttonStyle(.plain)
            .help("Tap: to-do → in progress → done")

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
                HStack(spacing: 4) {
                    if todo.source == .reminders {
                        Image(systemName: "list.bullet")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Synced from Apple Reminders")
                    }
                    Text(todo.title)
                        .strikethrough(todo.isCompleted)
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                        .fontWeight(todo.isInProgress ? .medium : .regular)
                        .lineLimit(2)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: beginEdit)
                .help("Double-click to edit")
            }

            Spacer(minLength: 4)

            if !isEditing, let label = todo.ageLabel() {
                AgePill(text: label, tier: todo.escalationTier(thresholds: appState.thresholds))
            }

            if !isEditing {
                Menu {
                    if todo.isCompleted {
                        Button("Reset to to-do") { appState.resetTodo(todo) }
                    } else if todo.isInProgress {
                        Button("Mark done") { appState.advanceTodo(todo) }
                        Button("Reset to to-do") { appState.resetTodo(todo) }
                    } else {
                        Button("Start") { appState.advanceTodo(todo) }
                    }
                    Button("Edit", action: beginEdit)
                    if showReschedule { Button("Bring to today") { appState.reschedule(todo) } }
                    if !todo.isCompleted {
                        Button("Delay to tomorrow") { appState.delay(todo) }
                    }
                    Button("Drop", role: .destructive) { appState.drop(todo) }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(hovering ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func beginEdit() {
        draft = todo.title
        isEditing = true
        fieldFocused = true
    }

    private func commitEdit() {
        appState.rename(todo, to: draft)
        isEditing = false
        fieldFocused = false
    }

    private func cancelEdit() {
        isEditing = false
        fieldFocused = false
    }

    private var todoStatusIcon: String {
        if todo.isCompleted { return "checkmark.circle.fill" }
        if todo.isInProgress { return "circle.lefthalf.filled" }
        return "circle"
    }

    private var todoStatusColor: Color {
        if todo.isCompleted { return .green }
        if todo.isInProgress { return .accentColor }
        return .secondary
    }
}

/// Stacked bar: done (green) + in progress (accent) in one track.
struct StackedTodoProgressBar: View {
    let done: Int
    let inProgress: Int
    let total: Int

    var body: some View {
        let denom = max(1, total)
        let doneFraction = CGFloat(done) / CGFloat(denom)
        let progressFraction = CGFloat(inProgress) / CGFloat(denom)

        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                    HStack(spacing: 0) {
                        if done > 0 {
                            Capsule()
                                .fill(Color.green)
                                .frame(width: width * doneFraction)
                        }
                        if inProgress > 0 {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: width * progressFraction)
                        }
                    }
                }
            }
            .frame(height: 6)

            HStack(spacing: 10) {
                if done > 0 {
                    Label("\(done) done", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if inProgress > 0 {
                    Label("\(inProgress) active", systemImage: "circle.lefthalf.filled")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.caption2)
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
