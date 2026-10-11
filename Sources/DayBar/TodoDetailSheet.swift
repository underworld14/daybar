import SwiftUI
import DayBarCore

/// Sheet for viewing/editing a task's title, description (`notes`), and local checklist.
struct TodoDetailSheet: View {
    var appState: AppState
    let todo: DailyTodo

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var newItemTitle = ""
    @State private var items: [TodoChecklistItem] = []
    @State private var selectedProjectID: UUID?
    @State private var plannedDate = Date.now
    @FocusState private var newItemFocused: Bool
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Task details")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button("Done") { saveAndDismiss() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Done (⌘↩)")
            }
            .padding()
            Divider()

            Form {
                TextField("Title", text: $title)

                Section("Project") {
                    Picker("Project", selection: $selectedProjectID) {
                        Text("None").tag(UUID?.none)
                        ForEach(appState.projects) { project in
                            Label(project.name, systemImage: project.symbolName)
                                .tag(UUID?.some(project.id))
                        }
                    }
                }

                Section("Planned For") {
                    DatePicker("Date", selection: $plannedDate, displayedComponents: .date)
                }

                Section {
                    TextEditor(text: $notes)
                        .font(.body)
                        .focused($descriptionFocused)
                        .frame(minHeight: 120, maxHeight: 180)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("Description")

                    if !detectedLinks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(detectedLinks, id: \.absoluteString) { url in
                                Link(destination: url) {
                                    Label(url.absoluteString, systemImage: "link")
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.top, 2)
                    }
                } header: {
                    Text("Description")
                } footer: {
                    Text("Line breaks are kept. Valid URLs become clickable links below.")
                        .font(.caption2)
                }

                Section {
                    ForEach(items, id: \.id) { item in
                        ChecklistRow(
                            item: item,
                            onToggle: {
                                appState.toggleChecklistItem(item)
                                reloadItems()
                            },
                            onRename: { newTitle in
                                appState.renameChecklistItem(item, to: newTitle)
                                reloadItems()
                            },
                            onDelete: {
                                appState.deleteChecklistItem(item)
                                reloadItems()
                            }
                        )
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.secondary)
                        TextField("Add checklist item", text: $newItemTitle)
                            .textFieldStyle(.plain)
                            .focused($newItemFocused)
                            .onSubmit(addItem)
                        if !newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Add", action: addItem)
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    let done = items.filter(\.isCompleted).count
                    Text(items.isEmpty ? "Checklist" : "Checklist (\(done)/\(items.count))")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 520)
        .onAppear(perform: load)
        .onDisappear(perform: persistTitleAndNotes)
        .onChange(of: selectedProjectID) { _, newID in
            appState.assign(todo: todo, to: appState.projects.first(where: { $0.id == newID }))
        }
        .onChange(of: plannedDate) { _, newDate in
            appState.setPlannedDate(todo, to: newDate)
        }
    }

    private var detectedLinks: [URL] {
        NotesLinkDetector.urls(in: notes)
    }

    private func load() {
        title = todo.title
        notes = todo.notes
        selectedProjectID = todo.projectID
        plannedDate = todo.plannedForDate
        reloadItems()
    }

    private func reloadItems() {
        items = appState.checklistItems(for: todo)
    }

    private func addItem() {
        guard appState.addChecklistItem(to: todo, title: newItemTitle) != nil else { return }
        newItemTitle = ""
        reloadItems()
        newItemFocused = true
    }

    /// Persist title/notes on any dismiss path (Done or Escape) so they match
    /// checklist items, which save immediately.
    private func persistTitleAndNotes() {
        appState.rename(todo, to: title)
        appState.updateNotes(todo, to: notes)
    }

    private func saveAndDismiss() {
        persistTitleAndNotes()
        dismiss()
    }
}


private struct ChecklistRow: View {
    let item: TodoChecklistItem
    var onToggle: () -> Void
    var onRename: (String) -> Void
    var onDelete: () -> Void

    @State private var draft = ""
    @State private var isEditing = false
    @State private var isHovered = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Mark complete")

            if isEditing {
                TextField("Item", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commitRename)
                    .onExitCommand {
                        isEditing = false
                        focused = false
                    }
                    .onChange(of: focused) { _, on in
                        if !on && isEditing { commitRename() }
                    }
            } else {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isEditing { onToggle() }
                    }
            }

            if !isEditing {
                Button(action: startEditing) {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1 : 0.45)
                .accessibilityLabel("Rename checklist item")
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0.45)
            .accessibilityLabel("Delete checklist item")
        }
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : .clear)
        )
        .onHover { isHovered = $0 }
    }

    private func startEditing() {
        draft = item.title
        isEditing = true
        focused = true
    }

    private func commitRename() {
        onRename(draft)
        isEditing = false
        focused = false
    }
}
