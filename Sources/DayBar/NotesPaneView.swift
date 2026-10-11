import SwiftUI
import DayBarCore

/// Notes pane: note list on the left (search, context menus), plain-text markdown editor
/// on the right with debounced autosave. Files live on disk; no markdown rendering (v1).
struct NotesPaneView: View {
    /// `nil` = All Notes (flat, across folders); otherwise a folder URL.
    let folder: URL?

    @Environment(AppState.self) private var appState

    @State private var allNotesInScope: [NotesStore.NoteFile] = []
    @State private var selectedNoteURL: URL?
    @State private var titleDraft = ""
    @State private var text = ""
    @State private var lastHandledNewNoteSignal = 0
    @State private var saveTask: Task<Void, Never>?
    @State private var notePendingRename: NotesStore.NoteFile?
    @State private var renameDraft = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        HSplitView {
            noteList
                .frame(minWidth: 200, idealWidth: 240, maxHeight: .infinity)

            editorPane
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            reloadNotes()
            handleNewNoteSignal()
        }
        .onChange(of: appState.windowNewNoteSignal) { _, _ in handleNewNoteSignal() }
        .onChange(of: selectedNoteURL) { _, newURL in
            flushPendingSave()
            loadNote(newURL)
        }
        .onChange(of: text) { _, newText in
            guard selectedNoteURL != nil else { return }
            scheduleSave(of: newText)
        }
        .onDisappear { flushPendingSave() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            flushPendingSave()
        }
        .alert(
            "Rename Note",
            isPresented: Binding(
                get: { notePendingRename != nil },
                set: { if !$0 { notePendingRename = nil } }
            )
        ) {
            TextField("Title", text: $renameDraft)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { notePendingRename = nil }
        } message: {
            Text("The file is renamed on disk.")
        }
    }

    // MARK: - List pane

    private var noteList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(folderCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    createNote()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help("New note")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            List(selection: $selectedNoteURL) {
                ForEach(visibleNotes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                            .lineLimit(1)
                            .font(.callout)
                        Text(note.modifiedAt, format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(note.url)
                    .contextMenu {
                        Button("Rename…") {
                            notePendingRename = note
                            renameDraft = note.title
                        }
                        Menu("Move to") {
                            Button("Root") { move(note, to: nil) }
                            ForEach(folders) { folder in
                                Button(folder.name) { move(note, to: folder.url) }
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) { delete(note) }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @State private var searchText = ""

    private var folders: [NotesStore.Folder] {
        (try? appState.notes.folders()) ?? []
    }

    private var folderCaption: String {
        folder?.lastPathComponent ?? "All Notes"
    }

    /// Search filters title + contents (case-insensitive contains) over the scope's notes.
    private var visibleNotes: [NotesStore.NoteFile] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allNotesInScope }
        let lowered = query.lowercased()
        return allNotesInScope.filter { note in
            if note.title.lowercased().contains(lowered) { return true }
            return ((try? appState.notes.contents(of: note.url)) ?? "")
                .lowercased()
                .contains(lowered)
        }
    }

    // MARK: - Editor pane

    @ViewBuilder
    private var editorPane: some View {
        if let url = selectedNoteURL {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("Title", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .onSubmit(commitTitle)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Divider()

                TextEditor(text: $text)
                    .font(.body)
                    .focused($editorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)

                Divider()
                HStack {
                    Text("\(wordCount) words")
                    Spacer()
                    if let note = allNotesInScope.first(where: { $0.url == url }) {
                        Text("Modified ")
                            + Text(note.modifiedAt, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        } else {
            ContentUnavailableView("No Note Selected", systemImage: "note.text")
        }
    }

    private var wordCount: Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.split(whereSeparator: \.isWhitespace).count
    }

    // MARK: - Actions

    private func reloadNotes() {
        if let folder {
            allNotesInScope = (try? appState.notes.notes(in: folder)) ?? []
        } else {
            allNotesInScope = (try? appState.notes.allNotes()) ?? []
        }
    }

    private func handleNewNoteSignal() {
        guard appState.windowNewNoteSignal != lastHandledNewNoteSignal else { return }
        lastHandledNewNoteSignal = appState.windowNewNoteSignal
        createNote()
    }

    private func createNote() {
        guard let url = try? appState.notes.createNote(in: folder) else { return }
        searchText = ""
        reloadNotes()
        selectedNoteURL = url
        titleDraft = url.deletingPathExtension().lastPathComponent
        text = ""
        editorFocused = true
    }

    private func loadNote(_ url: URL?) {
        guard let url else {
            titleDraft = ""
            text = ""
            return
        }
        titleDraft = url.deletingPathExtension().lastPathComponent
        text = (try? appState.notes.contents(of: url)) ?? ""
    }

    private func scheduleSave(of newText: String) {
        guard let url = selectedNoteURL else { return }
        saveTask?.cancel()
        saveTask = Task { [url, notesStore = appState.notes] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            try? notesStore.write(newText, to: url)
            await MainActor.run { reloadNotes() }
        }
    }

    /// Writes any pending debounced change immediately (view disappears / window closes).
    private func flushPendingSave() {
        guard let url = selectedNoteURL else { return }
        saveTask?.cancel()
        saveTask = nil
        let current = (try? appState.notes.contents(of: url)) ?? ""
        guard text != current else { return }
        try? appState.notes.write(text, to: url)
        reloadNotes()
    }

    private func commitTitle() {
        guard let url = selectedNoteURL else { return }
        let newTitle = titleDraft.trimmingCharacters(in: .whitespaces)
        guard !newTitle.isEmpty else {
            titleDraft = url.deletingPathExtension().lastPathComponent
            return
        }
        if let newURL = try? appState.notes.rename(url, to: newTitle) {
            selectedNoteURL = newURL
            reloadNotes()
        }
    }

    private func commitRename() {
        guard let note = notePendingRename else { return }
        notePendingRename = nil
        let newTitle = renameDraft.trimmingCharacters(in: .whitespaces)
        guard !newTitle.isEmpty, newTitle != note.title else { return }
        if let newURL = try? appState.notes.rename(note.url, to: newTitle) {
            if selectedNoteURL == note.url { selectedNoteURL = newURL }
            reloadNotes()
        }
    }

    private func move(_ note: NotesStore.NoteFile, to target: URL?) {
        guard (try? appState.notes.move(note.url, to: target)) != nil else { return }
        reloadNotes()
    }

    private func delete(_ note: NotesStore.NoteFile) {
        if selectedNoteURL == note.url {
            selectedNoteURL = nil
        }
        try? appState.notes.trash(note.url)
        reloadNotes()
    }
}
