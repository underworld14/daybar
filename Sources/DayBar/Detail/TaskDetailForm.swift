import SwiftUI
import DayBarCore
import MarkdownUI

/// Every editable field of a task, shared by the main window's inspector and the tray's
/// details sheet. Structural fields (status, priority, project, date) apply immediately;
/// the title commits on Return/blur and the description saves after a short pause, so
/// switching tasks never loses typing.
struct TaskDetailForm: View {
    var appState: AppState
    let todo: DailyTodo

    @State private var title = ""
    @State private var notes = ""
    /// What the fields held when last loaded or saved. Only text that differs from these was
    /// typed here, so only that is ever written back — a newer edit made elsewhere (tray,
    /// Reminders pull) is never overwritten by a stale copy.
    @State private var loadedTitle = ""
    @State private var loadedNotes = ""
    @State private var newItemTitle = ""
    @State private var items: [TodoChecklistItem] = []
    @State private var showsPreview = false
    @State private var notesSave: Task<Void, Never>?
    @FocusState private var titleFocused: Bool
    @FocusState private var newItemFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1...4)
                    .focused($titleFocused)
                    .onSubmit(commitTitle)
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { commitTitle() }
                    }
                    .accessibilityLabel("Title")
            }

            Section {
                Picker("Status", selection: statusBinding) {
                    Text("To Do").tag(BoardColumn.toDo)
                    Text("In Progress").tag(BoardColumn.inProgress)
                    Text("Done").tag(BoardColumn.done)
                }
                LabeledContent("Priority") {
                    HStack(spacing: ThemeMetrics.spacingM) {
                        PriorityGlyph(priority: todo.priority, showsEmpty: true)
                        Picker("Priority", selection: priorityBinding) {
                            ForEach([Priority.none, .low, .medium, .high], id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                Picker("Project", selection: projectBinding) {
                    Text("None").tag(UUID?.none)
                    ForEach(appState.projects) { project in
                        Label(project.name, systemImage: project.symbolName)
                            .tag(UUID?.some(project.id))
                    }
                }
                LabeledContent("Planned for") {
                    HStack(spacing: ThemeMetrics.spacingS) {
                        DatePicker("Planned for", selection: dateBinding, displayedComponents: .date)
                            .labelsHidden()
                        Button("Today") { appState.plan(todo, for: .now) }
                            .disabled(isPlanned(on: .now))
                        Button("Tomorrow") {
                            appState.plan(todo, for: DayMath.nextDay(.now, calendar: appState.calendar))
                        }
                        .disabled(isPlanned(on: DayMath.nextDay(.now, calendar: appState.calendar)))
                    }
                    .controlSize(.small)
                }
            }

            descriptionSection
            checklistSection

            Section {
                metadata
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onDisappear(perform: flush)
        .onChange(of: notes) { _, _ in scheduleNotesSave() }
        .onChange(of: todo.title) { _, newValue in adoptExternalTitle(newValue) }
        .onChange(of: todo.notes) { _, newValue in adoptExternalNotes(newValue) }
        .onChange(of: appState.checklistProgress[todo.id]) { _, _ in reloadItems() }
    }

    // MARK: - Sections

    private var descriptionSection: some View {
        Section {
            if showsPreview {
                Markdown(DescriptionMarkdown.autolinked(notes.isEmpty ? "_No description._" : notes))
                    .markdownTextStyle { ForegroundColor(.primary) }
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                    .textSelection(.enabled)
            } else {
                TextEditor(text: $notes)
                    .font(.body)
                    .frame(minHeight: 100, maxHeight: 220)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Description")
            }
            let links = NotesLinkDetector.urls(in: notes)
            if !links.isEmpty {
                ForEach(links, id: \.absoluteString) { url in
                    Link(destination: url) {
                        Label(url.absoluteString, systemImage: "link")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption)
                }
            }
        } header: {
            HStack {
                Text("Description")
                Spacer()
                Picker("Mode", selection: $showsPreview) {
                    Text("Write").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
            }
        } footer: {
            Text("Markdown is supported in Preview. Links become clickable.")
                .font(.caption2)
        }
    }

    private var checklistSection: some View {
        Section {
            ForEach(items, id: \.id) { item in
                ChecklistRowView(
                    item: item,
                    onToggle: { appState.toggleChecklistItem(item) },
                    onRename: { appState.renameChecklistItem(item, to: $0) },
                    onDelete: { appState.deleteChecklistItem(item) }
                )
            }
            HStack(spacing: ThemeMetrics.spacingM) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                TextField("Add checklist item", text: $newItemTitle)
                    .textFieldStyle(.plain)
                    .focused($newItemFocused)
                    .onSubmit(addItem)
            }
        } header: {
            let done = items.filter(\.isCompleted).count
            Text(items.isEmpty ? "Checklist" : "Checklist  \(done)/\(items.count)")
        }
    }

    private var metadata: some View {
        let created = todo.createdDate.formatted(date: .abbreviated, time: .omitted)
        var parts = ["Created \(created)"]
        if todo.delayCount > 0 { parts.append("Delayed \(todo.delayCount)×") }
        if todo.pomodoroCount > 0 { parts.append("\(todo.pomodoroCount) focus session\(todo.pomodoroCount == 1 ? "" : "s")") }
        if todo.source == .reminders { parts.append("Synced with Reminders") }
        return Text(parts.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Bindings straight to intents

    private var statusBinding: Binding<BoardColumn> {
        Binding(
            get: { todo.boardColumn },
            set: { column in withThemeAnimation(.columnMove) { appState.setBoardStatus(column, for: todo) } }
        )
    }

    private var priorityBinding: Binding<Priority> {
        Binding(get: { todo.priority }, set: { appState.setPriority(todo, $0) })
    }

    private var projectBinding: Binding<UUID?> {
        Binding(
            get: { todo.projectID },
            set: { id in appState.assign(todo: todo, to: appState.projects.first(where: { $0.id == id })) }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { todo.plannedForDate }, set: { appState.setPlannedDate(todo, to: $0) })
    }

    private func isPlanned(on day: Date) -> Bool {
        DayMath.startOfDay(todo.plannedForDate, calendar: appState.calendar) == DayMath.startOfDay(day, calendar: appState.calendar)
    }

    // MARK: - Persistence

    private func load() {
        title = todo.title
        loadedTitle = title
        notes = todo.notes
        loadedNotes = notes
        reloadItems()
    }

    /// The task was renamed elsewhere: show it, unless the user is mid-edit here.
    private func adoptExternalTitle(_ newValue: String) {
        guard !titleFocused, title == loadedTitle, newValue != title else { return }
        title = newValue
        loadedTitle = newValue
    }

    /// The description changed elsewhere: show it, unless there are unsaved edits here. Our
    /// own save comes back trimmed; that echo must not rewrite the editor under the cursor.
    private func adoptExternalNotes(_ newValue: String) {
        guard notes == loadedNotes,
              newValue != notes.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        notes = newValue
        loadedNotes = newValue
    }

    private func reloadItems() {
        items = appState.checklistItems(for: todo)
    }

    private func commitTitle() {
        guard title != loadedTitle else { return }
        appState.rename(todo, to: title)
        title = todo.title
        loadedTitle = title
    }

    private func scheduleNotesSave() {
        notesSave?.cancel()
        guard notes != loadedNotes else { return }
        notesSave = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveNotes()
        }
    }

    private func saveNotes() {
        guard notes != loadedNotes else { return }
        appState.updateNotes(todo, to: notes)
        loadedNotes = notes
    }

    /// Saves pending edits when the form goes away (task switch, sheet close, window close).
    private func flush() {
        notesSave?.cancel()
        // A permanently deleted task must not be touched (its backing data is gone).
        guard !todo.isDeleted, todo.modelContext != nil else { return }
        commitTitle()
        saveNotes()
    }

    private func addItem() {
        guard appState.addChecklistItem(to: todo, title: newItemTitle) != nil else { return }
        newItemTitle = ""
        newItemFocused = true
    }
}
