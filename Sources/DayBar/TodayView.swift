import AppKit
import SwiftUI
import DayBarCore

/// The menu-bar panel: quick-add, today's list, the carry-over backlog, and the Pomodoro
/// control strip. Multi-add quick-add (Return adds and keeps focus) is the morning ritual.
struct TodayView: View {
    @Environment(AppState.self) private var appState
    /// Present when hosted in the menu-bar panel, which sizes itself from these measurements.
    @Environment(TrayLayoutModel.self) private var trayLayout: TrayLayoutModel?
    @Environment(TrayInteractionModel.self) private var interaction: TrayInteractionModel?

    @State private var newTitle = ""
    @FocusState private var addFocused: Bool
    @State private var showSettings = false
    @State private var showStats = false
    @State private var showHistory = false
    @State private var addForTomorrow = false
    @State private var detailTodo: DailyTodo?


    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            quickAdd
            // Always mounted (an empty card has no height) so the first started task shows
            // up in place inside the long-lived panel host, like the Tomorrow section.
            NowCard(appState: appState, onOpenDetails: { detailTodo = $0 })
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
            ScrollViewReader { proxy in
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
            .onChange(of: interaction?.selectedTodoID) { _, id in
                guard let id else { return }
                withThemeAnimation(.snap) { proxy.scrollTo(id) }
            }
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
            interaction?.openDetails = { detailTodo = $0 }
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
            Text("DayBar").font(ThemeTypography.wordmark)
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

    private var quickAdd: some View {
        QuickAddField(
            text: $newTitle,
            addForTomorrow: $addForTomorrow,
            focused: $addFocused,
            projects: projectRefs,
            onSubmit: addCurrent,
            onActivate: claimQuickAddFocus
        )
        .onChange(of: addFocused) { _, focused in
            if focused { ensureQuickAddKeyWindow() }
        }
    }

    private var projectRefs: [QuickAddParser.ProjectRef] {
        appState.projects.map { QuickAddParser.ProjectRef(id: $0.id, name: $0.name) }
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
        guard let parsed = QuickAddParser.parse(newTitle, projects: projectRefs) else { return }
        let tomorrow = parsed.day.map { $0 == .tomorrow } ?? addForTomorrow
        let day = tomorrow ? DayMath.nextDay(.now, calendar: appState.calendar) : Date.now
        withThemeAnimation(.reorder) {
            _ = appState.addTodo(TodoDraft(
                title: parsed.title,
                priority: parsed.priority ?? .none,
                plannedFor: day,
                projectID: parsed.projectID
            ))
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
                TaskRowStack {
                    ForEach(appState.todayHabits) { habit in
                        HabitRow(appState: appState, habit: habit)
                            .id("\(habit.log.id)-\(habit.log.statusRaw)")
                    }
                }
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader("Today") {
                todoProgressLabel
            }
            Group {
                if appState.todayTodos.isEmpty {
                    Text("Nothing planned yet. What matters today?")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TaskRowStack {
                        ForEach(trayToday) { todo in
                            TodoRow(appState: appState, todo: todo, section: trayToday, onOpenDetails: { detailTodo = todo })
                                .id(todo.id)
                        }
                    }
                }
            }
            .modifier(daySectionDropZone("tray.today", tasks: trayToday, day: .now))
        }
    }

    /// Drop target for a day section: reorders within it, or re-plans a task dragged in
    /// from another section (Today ↔ Tomorrow, Carried → either).
    private func daySectionDropZone(_ zoneID: String, tasks: [DailyTodo], day: Date) -> TaskDropZone {
        let open = tasks.filter { $0.completedDate == nil }
        return TaskDropZone(
            zoneID: zoneID,
            orderedIDs: tasks.map(\.id),
            reorderableCount: open.count,
            accepts: { id in trayTask(id).map { !$0.isCompleted } ?? false },
            onDrop: { id, index in
                guard let todo = trayTask(id), !todo.isCompleted else { return false }
                if open.contains(where: { $0.id == id }) {
                    appState.moveTodo(todo, toIndex: index, in: open)
                } else {
                    appState.moveTodo(todo, toDay: day, index: index, in: open)
                }
                return true
            }
        )
    }

    /// Today's tasks minus the ones in progress (those sit in the Now card).
    private var trayToday: [DailyTodo] { appState.todayTodos.filter { !$0.isInProgress } }
    private var trayCarried: [DailyTodo] { appState.carriedTodos.filter { !$0.isInProgress } }

    private func trayTask(_ id: UUID) -> DailyTodo? {
        (appState.todayTodos + appState.tomorrowTodos + appState.carriedTodos).first(where: { $0.id == id })
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
                ForEach(trayCarried) { todo in
                    TodoRow(
                        appState: appState, todo: todo, section: trayCarried,
                        showReschedule: true, onOpenDetails: { detailTodo = todo }
                    )
                    .id(todo.id)
                }
            }
            .taskDropZone(
                "tray.carried",
                orderedIDs: trayCarried.map(\.id),
                reorderableCount: trayCarried.count,
                // Carried tasks only reorder among themselves; nothing is dragged into the past.
                accepts: { id in trayCarried.contains(where: { $0.id == id }) },
                onDrop: { id, index in
                    guard let todo = trayCarried.first(where: { $0.id == id }) else { return false }
                    appState.moveTodo(todo, toIndex: index, in: trayCarried)
                    return true
                }
            )
        }
    }

    private var tomorrowSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader("Tomorrow") {
                Text("\(appState.tomorrowTodos.count)")
            }
            Group {
                if appState.tomorrowTodos.isEmpty {
                    Text("Nothing planned for tomorrow yet.")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TaskRowStack {
                        ForEach(appState.tomorrowTodos) { todo in
                            TodoRow(appState: appState, todo: todo, section: appState.tomorrowTodos, onOpenDetails: { detailTodo = todo })
                                .id(todo.id)
                        }
                    }
                }
            }
            .modifier(daySectionDropZone(
                "tray.tomorrow", tasks: appState.tomorrowTodos,
                day: DayMath.nextDay(.now, calendar: appState.calendar)
            ))
        }
    }
}

/// A single habit row: status ring (same control as tasks), title, cue, streak chip, and a
/// hover-revealed actions menu.
struct HabitRow: View {
    var appState: AppState
    let habit: TodayHabit

    @State private var hovering = false

    private var isSkipped: Bool { habit.log.status == .skipped }

    var body: some View {
        HStack(spacing: ThemeMetrics.spacingS) {
            if isSkipped {
                Button { appState.toggleHabit(habit.log) } label: {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                        .overlay(Rectangle().fill(Color.secondary).frame(width: 7, height: 1.5))
                        .frame(width: ThemeMetrics.statusRingSize, height: ThemeMetrics.statusRingSize)
                        .frame(width: ThemeMetrics.statusHitSize, height: ThemeMetrics.statusHitSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Skipped today. Click to mark incomplete.")
                .accessibilityLabel("Skipped habit")
            } else {
                StatusToggle(
                    status: habit.log.isCompleted ? .done : .toDo,
                    onToggleComplete: { appState.toggleHabit(habit.log) },
                    onToggleInProgress: { appState.toggleHabit(habit.log) },
                    allowsInProgress: false
                )
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(habit.template.title)
                    .strikethrough(habit.log.isCompleted)
                    .foregroundStyle(habit.log.isCompleted || isSkipped ? .secondary : .primary)
                    .lineLimit(1)
                if !habit.template.cueText.isEmpty {
                    Text(habit.template.cueText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: ThemeMetrics.spacingXS)

            if habit.template.remindersSyncEnabled, habit.template.externalReminderIdentifier != nil {
                Image(systemName: "list.bullet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Synced with Reminders")
            }

            if habit.currentStreak > 0 {
                Chip(text: "\(habit.currentStreak)d", tint: ThemeColors.statusDone)
                    .help(habit.graceRemaining > 0 ? "\(habit.graceRemaining) grace day left this week" : "No grace days left this week")
                    .accessibilityLabel("Streak \(habit.currentStreak) days")
            }

            Menu {
                if habit.log.isCompleted || isSkipped {
                    Button("Mark Incomplete") { appState.toggleHabit(habit.log) }
                } else {
                    Button("Skip Today") { appState.skipHabit(habit.log) }
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
        .padding(.vertical, ThemeMetrics.rowVerticalPadding)
        .padding(.horizontal, ThemeMetrics.rowHorizontalPadding)
        .background {
            RoundedRectangle(cornerRadius: ThemeMetrics.rowRadius, style: .continuous)
                .fill(hovering ? ThemeColors.rowHover : .clear)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }
}

/// A tray task row: `TaskRowView` wired to the tray's intents. One click on the ring
/// completes; the flag sets priority; the ellipsis/context menu holds the rest.
struct TodoRow: View {
    var appState: AppState
    let todo: DailyTodo
    /// The row's section in display order — the list Move Up/Down/To Top work within.
    var section: [DailyTodo] = []
    var showReschedule = false
    var onOpenDetails: (() -> Void)? = nil

    @Environment(TrayInteractionModel.self) private var interaction: TrayInteractionModel?
    @Environment(TaskDragCoordinator.self) private var dragCoordinator: TaskDragCoordinator?

    var body: some View {
        var actions = TaskRowActions.make(todo, appState: appState, openDetails: onOpenDetails)
        let id = todo.id
        actions.hoverChanged = { [interaction] hovering in interaction?.hoverChanged(id, hovering: hovering) }
        return row(actions: actions)
            .opacity(dragCoordinator?.draggingID == todo.id ? 0.35 : 1)
            .taskRowFrame(todo.id)
    }

    @ViewBuilder
    private func row(actions: TaskRowActions) -> some View {
        let base = TaskRowView(
            configuration: .make(
                todo, appState: appState, showsAge: true,
                isSelected: interaction?.selectedTodoID == todo.id
            ),
            actions: actions
        ) {
            TrayTaskMenu(
                appState: appState, todo: todo, section: section,
                showReschedule: showReschedule, onOpenDetails: onOpenDetails
            )
        }
        if todo.isCompleted {
            base
        } else {
            base.taskDraggable(todo.id, title: todo.title, coordinator: dragCoordinator)
        }
    }
}

/// Actions for a tray task (ellipsis button + right-click).
struct TrayTaskMenu: View {
    var appState: AppState
    let todo: DailyTodo
    var section: [DailyTodo] = []
    var showReschedule = false
    var onOpenDetails: (() -> Void)?

    private var movable: [DailyTodo] { section.filter { $0.completedDate == nil } }

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
        if !todo.isCompleted, movable.count > 1 {
            Divider()
            let index = movable.firstIndex(where: { $0.id == todo.id })
            Button("Move to Top") { withThemeAnimation(.reorder) { appState.moveTodoToTop(todo, in: movable) } }
                .disabled(index == 0)
            Button("Move Up  ⌘↑") { withThemeAnimation(.reorder) { appState.moveTodo(todo, by: -1, in: movable) } }
                .disabled(index == 0)
            Button("Move Down  ⌘↓") { withThemeAnimation(.reorder) { appState.moveTodo(todo, by: 1, in: movable) } }
                .disabled(index == movable.count - 1)
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
            Group {
                if pomo.phase == .work, let task = appState.focusTodo {
                    Text("Focus · \(task.title)")
                } else {
                    Text(pomo.phase == .idle ? "Focus" : pomo.phase.displayName)
                }
            }
            .font(.subheadline)
            .lineLimit(1)

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
