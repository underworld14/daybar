import SwiftUI
import DayBarCore

/// Sidebar selection for the main window. App-layer (URLs aren't a Core concern).
enum SidebarSelection: Hashable {
    case today
    case tomorrow
    case allTasks
    case project(UUID)
    case allNotes
    case folder(URL)
}

/// The main window: tasks (list/kanban, groupable by project) + markdown notes.
struct MainWindowView: View {
    @Environment(AppState.self) private var appState

    @State private var selection: SidebarSelection? = .today
    /// The board's selected task (by id, never a model reference) and the inspector toggle.
    @State private var selectedTodoID: UUID?
    @State private var inspectorPresented = false
    /// Sidebar row currently under a dragged task.
    @State private var dropTarget: SidebarSelection?
    @State private var showProjectSheet = false
    @State private var projectSheetMode: ProjectSheetMode = .create
    @State private var projectPendingDelete: Project?
    @State private var showNewFolderSheet = false
    @State private var pendingFolderRename: NotesStore.Folder?
    @State private var folderPendingDelete: NotesStore.Folder?
    /// Cached so the sidebar doesn't hit the disk on every render.
    @State private var folders: [NotesStore.Folder] = []

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                .navigationTitle("DayBar")
        } detail: {
            detail
                .inspector(isPresented: Binding(
                    get: { inspectorPresented && isTaskScope },
                    set: { inspectorPresented = $0 }
                )) {
                    TaskInspectorView(appState: appState, selectedID: selectedTodoID)
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
                }
        }
        .onAppear {
            appState.refresh()
            reloadFolders()
        }
        // Folders can change outside the app (Finder, sync): re-read when a window activates.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            reloadFolders()
        }
        .onChange(of: appState.projects) { _, projects in
            // A deleted project must not leave a dead selection.
            if case .project(let id) = selection, !projects.contains(where: { $0.id == id }) {
                selection = .today
            }
        }
        .onChange(of: selection) { _, _ in
            selectedTodoID = nil
        }
        .onChange(of: appState.windowCommand) { _, request in
            if request?.command == .toggleInspector, isTaskScope { inspectorPresented.toggle() }
        }
        .onChange(of: appState.windowNewNoteSignal) { _, _ in
            // Route to the notes pane; NotesPaneView itself creates the note.
            switch selection {
            case .allNotes, .folder: break
            default: selection = .allNotes
            }
        }
        .sheet(isPresented: $showProjectSheet) {
            ProjectSheet(mode: projectSheetMode) { name, symbol, existing in
                switch existing {
                case .some(let project):
                    appState.renameProject(project, to: name, symbolName: symbol)
                case nil:
                    appState.createProject(name: name, symbolName: symbol)
                }
            }
        }
        .sheet(isPresented: $showNewFolderSheet) {
            TextEntrySheet(
                title: "New Folder",
                placeholder: "Folder name",
                initialText: ""
            ) { name in
                _ = try? appState.notes.createFolder(named: name)
                reloadFolders()
            }
        }
        .alert(
            "Delete project “\(projectPendingDelete?.name ?? "")”?",
            isPresented: Binding(
                get: { projectPendingDelete != nil },
                set: { if !$0 { projectPendingDelete = nil } }
            )
        ) {
            Button("Delete Project", role: .destructive) {
                if let project = projectPendingDelete { appState.deleteProject(project) }
                projectPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { projectPendingDelete = nil }
        } message: {
            Text("Its tasks stay, but they will no longer belong to a project.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Tasks") {
                    Label("Today", systemImage: "calendar")
                        .modifier(taskDrop(.today))
                        .tag(SidebarSelection.today)
                    Label("Tomorrow", systemImage: "calendar.badge.clock")
                        .modifier(taskDrop(.tomorrow))
                        .tag(SidebarSelection.tomorrow)
                    Label("All Tasks", systemImage: "tray.full")
                        .tag(SidebarSelection.allTasks)

                    ForEach(appState.projects) { project in
                        HStack(spacing: 6) {
                            Label(project.name, systemImage: project.symbolName)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            let count = appState.openTaskCount(forProject: project.id)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .modifier(taskDrop(.project(project.id)))
                        .tag(SidebarSelection.project(project.id))
                        .contextMenu {
                            Button("Rename…") {
                                projectSheetMode = .rename(project)
                                showProjectSheet = true
                            }
                            Button("Delete…", role: .destructive) {
                                projectPendingDelete = project
                            }
                        }
                    }
                }

                Section("Notes") {
                    Label("All Notes", systemImage: "note.text")
                        .tag(SidebarSelection.allNotes)
                        .contextMenu {
                            Button("New Folder…") { showNewFolderSheet = true }
                        }
                    ForEach(folders) { folder in
                        Label(folder.name, systemImage: "folder")
                            .lineLimit(1)
                            .tag(SidebarSelection.folder(folder.url))
                            .contextMenu {
                                Button("New Folder…") { showNewFolderSheet = true }
                                Button("Rename…") { pendingFolderRename = folder }
                                Button("Delete…", role: .destructive) {
                                    folderPendingDelete = folder
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Button {
                    projectSheetMode = .create
                    showProjectSheet = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(10)
                Spacer()
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingFolderRename != nil },
            set: { if !$0 { pendingFolderRename = nil } }
        )) {
            if let folder = pendingFolderRename {
                TextEntrySheet(
                    title: "Rename Folder",
                    placeholder: "Folder name",
                    initialText: folder.name
                ) { name in
                    _ = try? appState.notes.renameFolder(folder.url, to: name)
                    reloadFolders()
                }
            }
        }
        .alert(
            "Delete folder “\(folderPendingDelete?.name ?? "")”?",
            isPresented: Binding(
                get: { folderPendingDelete != nil },
                set: { if !$0 { folderPendingDelete = nil } }
            )
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderPendingDelete {
                    try? appState.notes.trash(folder.url)
                    reloadFolders()
                }
                folderPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { folderPendingDelete = nil }
        } message: {
            Text("The folder and all notes inside move to the Trash.")
        }
    }

    /// Dropping a task on Today/Tomorrow re-plans it (bottom of that day); on a project,
    /// assigns it. The row highlights while a task hovers over it.
    private func taskDrop(_ target: SidebarSelection) -> SidebarTaskDrop {
        SidebarTaskDrop(target: target, isTargeted: dropTarget == target) { targeted in
            if targeted {
                dropTarget = target
            } else if dropTarget == target {
                dropTarget = nil
            }
        } perform: { id in
            guard let todo = try? appState.store.todo(id: id), todo.status != .dropped else { return false }
            switch target {
            case .today:
                appState.setPlannedDate(todo, to: .now)
            case .tomorrow:
                appState.setPlannedDate(todo, to: DayMath.nextDay(.now, calendar: appState.calendar))
            case .project(let projectID):
                appState.assign(todo: todo, to: appState.projects.first(where: { $0.id == projectID }))
            default:
                return false
            }
            return true
        }
    }

    private func reloadFolders() {
        folders = (try? appState.notes.folders()) ?? []
    }

    // MARK: - Detail

    private func board(_ scope: TaskScope) -> some View {
        TaskBoardView(scope: scope, selection: $selectedTodoID, inspectorPresented: $inspectorPresented)
    }

    private var isTaskScope: Bool {
        switch selection {
        case .today, .tomorrow, .allTasks, .project: return true
        case .allNotes, .folder, nil: return false
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .today:
            board(.today).id(SidebarSelection.today)
        case .tomorrow:
            board(.tomorrow).id(SidebarSelection.tomorrow)
        case .allTasks:
            board(.allTasks).id(SidebarSelection.allTasks)
        case .project(let id):
            board(.project(id)).id(SidebarSelection.project(id))
        case .allNotes:
            NotesPaneView(folder: nil).id(SidebarSelection.allNotes)
        case .folder(let url):
            NotesPaneView(folder: url).id(SidebarSelection.folder(url))
        case nil:
            ContentUnavailableView("DayBar", systemImage: "checklist")
        }
    }
}

enum ProjectSheetMode {
    case create
    case rename(Project)
}

/// New/rename project sheet: name field + curated SF Symbol grid.
struct ProjectSheet: View {
    let mode: ProjectSheetMode
    let onCommit: (String, String, Project?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "folder"

    private let symbols = [
        "folder", "briefcase", "house", "book", "wrench.and.screwdriver",
        "graduationcap", "heart", "leaf", "flame", "bolt", "globe", "music.note",
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text(sheetTitle).font(.headline)
            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 6), spacing: 8) {
                ForEach(symbols, id: \.self) { candidate in
                    Button {
                        symbol = candidate
                    } label: {
                        Image(systemName: candidate)
                            .frame(width: 32, height: 32)
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(symbol == candidate ? Color.accentColor.opacity(0.2) : .clear)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        symbol == candidate ? Color.accentColor : .clear,
                                        lineWidth: 1.5
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(commitLabel, action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear(perform: load)
    }

    private var sheetTitle: String {
        if case .rename = mode { return "Rename Project" }
        return "New Project"
    }

    private var commitLabel: String {
        if case .rename = mode { return "Rename" }
        return "Create"
    }

    private func load() {
        switch mode {
        case .create:
            break
        case .rename(let project):
            name = project.name
            symbol = project.symbolName
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let existing: Project?
        if case .rename(let project) = mode {
            existing = project
        } else {
            existing = nil
        }
        onCommit(trimmed, symbol, existing)
        dismiss()
    }
}

/// Small sheet with a single text field (new/rename folder).
struct TextEntrySheet: View {
    let title: String
    let placeholder: String
    let initialText: String
    let onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.headline)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("OK", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 280)
        .onAppear {
            text = initialText
            focused = true
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
        dismiss()
    }
}
