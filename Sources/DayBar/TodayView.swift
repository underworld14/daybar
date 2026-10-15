import AppKit
import SwiftUI
import DayBarCore

/// The menu-bar panel: quick-add, today's list, the carry-over backlog, and the Pomodoro
/// control strip. Multi-add quick-add (Return adds and keeps focus) is the morning ritual.
struct TodayView: View {
    @Environment(AppState.self) private var appState
    /// Present when hosted in the menu-bar panel, which sizes itself from these measurements.
    @Environment(TrayLayoutModel.self) private var trayLayout: TrayLayoutModel?

    @State private var newTitle = ""
    @FocusState private var addFocused: Bool
    @State private var showSettings = false
    @State private var showStats = false
    @State private var showHistory = false
    @State private var addForTomorrow = false
    @State private var detailTodo: DailyTodo?

    private let wordmarkFont = Font.system(size: 15, weight: .bold, design: .rounded)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            quickAdd
            if appState.totalTodayCount > 0 { progressBar }
            if let entry = appState.focusStreakEntry {
                DayscapeStrip(
                    cells: entry.weekCells,
                    currentStreak: entry.streak.current,
                    graceRemaining: entry.streak.graceRemaining
                )
            }
            UndoToast(appState: appState, style: .inline)
            Divider().padding(.top, 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    habitsSection
                    todaySection
                    if TraySectionPolicy.showsTomorrowSection(todoCount: appState.tomorrowTodos.count) {
                        tomorrowSection
                    }
                    if !appState.carriedTodos.isEmpty { carriedSection }
                }
                .padding(.vertical, 2)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    trayLayout?.setContentHeight(height)
                }
            }
            .frame(maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                trayLayout?.setViewportHeight(height)
            }
            Divider()
            LofiRadioStrip()
            PomodoroStrip(appState: appState)
        }
        .padding(14)
        .frame(width: 360)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            trayLayout?.setRootHeight(height)
        }
        .onAppear {
            appState.refresh()
            DispatchQueue.main.async { claimQuickAddFocus() }
            Task { await appState.loadRadioChannels() }
        }
        .onChange(of: appState.quickAddFocusSignal) { _, _ in claimQuickAddFocus() }
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState)
        }
        .sheet(isPresented: $showStats) {
            AnalyticsView(appState: appState)
        }
        .sheet(isPresented: $showHistory) {
            TaskHistoryView(appState: appState)
        }
        .sheet(item: $detailTodo) { todo in
            TodoDetailSheet(appState: appState, todo: todo)
        }
        .onChange(of: showSettings) { _, open in
            appState.isPanelSheetPresented = open || showStats || showHistory || detailTodo != nil
        }
        .onChange(of: showStats) { _, open in
            appState.isPanelSheetPresented = open || showSettings || showHistory || detailTodo != nil
        }
        .onChange(of: showHistory) { _, open in
            appState.isPanelSheetPresented = open || showSettings || showStats || detailTodo != nil
        }
        .onChange(of: detailTodo) { _, todo in
            appState.isPanelSheetPresented = todo != nil || showSettings || showStats || showHistory
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
                Button {
                    NotificationCenter.default.post(name: AppDelegate.openMainWindowNotification, object: nil)
                } label: { Label("Open DayBar…", systemImage: "macwindow") }
                Button { showSettings = true } label: { Label("Settings…", systemImage: "gearshape") }
                Button { showStats = true } label: { Label("Statistics…", systemImage: "chart.bar") }
                Button { showHistory = true } label: { Label("Task History…", systemImage: "clock.arrow.circlepath") }
                Button { appState.presentEndOfDayReview = true } label: { Label("Review day…", systemImage: "checkmark.circle") }
                Divider()
                Button("Quit DayBar") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Menu")
            .help("Settings and more")
        }
    }

    // MARK: - Quick add

    private var trimmed: String { newTitle.trimmingCharacters(in: .whitespaces) }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Plan for", selection: $addForTomorrow) {
                Text("Today").tag(false)
                Text("Tomorrow").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                Button(action: claimQuickAddFocus) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(addFocused ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Focus quick-add")

                ZStack(alignment: .leading) {
                    TextField(addForTomorrow ? "Add a task for tomorrow…" : "Add a task for today…", text: $newTitle)
                        .textFieldStyle(.plain)
                        .focused($addFocused)
                        .tint(.accentColor)
                        .onSubmit(addCurrent)

                    // Borderless nonactivating panels often omit AppKit's insertion point
                    // even when FocusState is true — draw one while the field is empty.
                    if addFocused && newTitle.isEmpty {
                        BlinkingInsertionCaret()
                            .padding(.leading, 1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }

                if !trimmed.isEmpty {
                    Button(action: addCurrent) {
                        Image(systemName: "return").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Add task")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture { claimQuickAddFocus() }
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(addFocused ? 0.08 : 0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        addFocused ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: addFocused ? 1.5 : 1
                    )
            }
            .animation(.easeInOut(duration: 0.12), value: addFocused)
            .onChange(of: addFocused) { _, focused in
                if focused { ensureQuickAddKeyWindow() }
            }
        }
    }

    /// Activate the app, make the floating panel key, then focus the field so typing works
    /// and the caret/affordance are visible.
    private func claimQuickAddFocus() {
        ensureQuickAddKeyWindow()
        addFocused = true
    }

    private func ensureQuickAddKeyWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let panel = NSApp.windows.first(where: { $0 is FloatingPanel && $0.isVisible }) {
            panel.makeKeyAndOrderFront(nil)
        } else {
            NSApp.keyWindow?.makeKey()
        }
    }

    private func addCurrent() {
        if addForTomorrow {
            appState.addTodoForTomorrow(title: newTitle)
        } else {
            appState.addTodo(title: newTitle)
        }
        newTitle = ""
        claimQuickAddFocus() // keep the field hot for multi-add
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
            SectionHeader("Habits") {
                if appState.totalHabitsTodayCount > 0 {
                    Text("\(appState.completedHabitsTodayCount)/\(appState.totalHabitsTodayCount)")
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
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader("Today") {
                todoProgressLabel
            }
            if appState.todayTodos.isEmpty {
                Text("Nothing planned yet. What matters today?")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 2)
            } else {
                TaskRowStack {
                    ForEach(appState.todayTodos) { todo in
                        TodoRow(appState: appState, todo: todo, onOpenDetails: { detailTodo = todo })
                            .id(todo.id)
                    }
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
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader("Carried over") {
                if appState.overdueCount > 0 {
                    Text("\(appState.overdueCount) aging").foregroundStyle(ThemeColors.aging)
                }
            }
            TaskRowStack {
                ForEach(appState.carriedTodos) { todo in
                    TodoRow(appState: appState, todo: todo, showReschedule: true, onOpenDetails: { detailTodo = todo })
                }
            }
        }
    }

    private var tomorrowSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader("Tomorrow") {
                Text("\(appState.tomorrowTodos.count)")
            }
            if appState.tomorrowTodos.isEmpty {
                Text("Nothing planned for tomorrow yet.")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 2)
            } else {
                TaskRowStack {
                    ForEach(appState.tomorrowTodos) { todo in
                        TodoRow(appState: appState, todo: todo, onOpenDetails: { detailTodo = todo })
                            .id(todo.id)
                    }
                }
            }
        }
    }
}

/// Visible typing caret for empty focused fields. AppKit often suppresses the real
/// insertion point inside borderless nonactivating panels.
private struct BlinkingInsertionCaret: View {
    @State private var visible = true

    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 2, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.53).repeatForever(autoreverses: true)) {
                    visible = false
                }
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
                Image(systemName: habitStatusIcon)
                    .foregroundStyle(habitStatusColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(habitAccessibilityLabel)
            .help(habitAccessibilityLabel)

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

            if habit.template.remindersSyncEnabled, habit.template.externalReminderIdentifier != nil {
                Image(systemName: "list.bullet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Synced with Reminders")
            }

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
            .opacity(hovering ? 1 : 0.35)
            .accessibilityLabel("Habit actions")
            .help("Habit actions")
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var habitStatusIcon: String {
        if habit.log.isCompleted { return "checkmark.circle.fill" }
        if habit.log.status == .skipped { return "minus.circle" }
        return "circle"
    }

    private var habitStatusColor: Color {
        if habit.log.isCompleted { return .green }
        if habit.log.status == .skipped { return .secondary.opacity(0.7) }
        return .secondary
    }

    private var habitAccessibilityLabel: String {
        if habit.log.isCompleted { return "Completed habit" }
        if habit.log.status == .skipped { return "Skipped habit" }
        return "Pending habit"
    }
}

/// A tray task row: `TaskRowView` wired to the tray's intents. One click on the ring
/// completes; the flag sets priority; the ellipsis/context menu holds the rest.
struct TodoRow: View {
    var appState: AppState
    let todo: DailyTodo
    var showReschedule = false
    var onOpenDetails: (() -> Void)? = nil

    var body: some View {
        TaskRowView(
            configuration: .make(todo, appState: appState, showsAge: true),
            actions: .make(todo, appState: appState, openDetails: onOpenDetails)
        ) {
            TrayTaskMenu(appState: appState, todo: todo, showReschedule: showReschedule, onOpenDetails: onOpenDetails)
        }
    }
}

/// Actions for a tray task (ellipsis button + right-click).
struct TrayTaskMenu: View {
    var appState: AppState
    let todo: DailyTodo
    var showReschedule = false
    var onOpenDetails: (() -> Void)?

    var body: some View {
        if todo.isCompleted {
            Button("Reset to To-Do") { appState.resetTodo(todo) }
        } else {
            Button("Complete") { withThemeAnimation(.reorder) { appState.toggleComplete(todo) } }
            if todo.isInProgress {
                Button("Move Back to To-Do") { appState.resetTodo(todo) }
            } else {
                Button("Start") { appState.startTodo(todo) }
            }
        }
        Button("Details…") { onOpenDetails?() }
        Menu("Priority") {
            ForEach([Priority.high, .medium, .low, .none], id: \.self) { level in
                Button {
                    appState.setPriority(todo, level)
                } label: {
                    if level == todo.priority {
                        Label(level.displayName, systemImage: "checkmark")
                    } else {
                        Text(level.displayName)
                    }
                }
            }
        }
        Divider()
        if showReschedule { Button("Bring to Today") { appState.reschedule(todo) } }
        if !todo.isCompleted {
            Button("Delay to Tomorrow") { appState.delay(todo) }
        }
        Button("Drop", role: .destructive) { appState.drop(todo) }
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
            .help(pomo.isRunning ? "Pause" : "Start")
            .accessibilityLabel(pomo.isRunning ? "Pause focus" : "Start focus")

            Button { appState.stopPomodoro() } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Stop session")
            .accessibilityLabel("Stop focus session")

            if pomo.phase.isBreak {
                Button { appState.skipBreakAndStartWork() } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Skip break")
                .accessibilityLabel("Skip break")
            }
        }
    }
}
