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
    }

    private var detectedLinks: [URL] {
        NotesLinkDetector.urls(in: notes)
    }

    private func load() {
        title = todo.title
        notes = todo.notes
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
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Completed" : "Incomplete")

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
                    .onTapGesture(count: 2) {
                        draft = item.title
                        isEditing = true
                        focused = true
                    }
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete checklist item")
        }
    }

    private func commitRename() {
        onRename(draft)
        isEditing = false
        focused = false
    }
}
