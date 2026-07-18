import SwiftUI
import DayBarCore

/// Apple Reminders sync controls inside Settings.
struct RemindersSettingsSection: View {
    var appState: AppState

    @AppStorage(PreferenceKeys.remindersSyncEnabled) private var syncEnabled = false
    @AppStorage(PreferenceKeys.remindersIncludeUndated) private var includeUndated = true
    @AppStorage(PreferenceKeys.remindersPushNewTodos) private var pushNewTodos = false
    @AppStorage(PreferenceKeys.defaultReminderCalendarID) private var defaultListID = ""
    @AppStorage(PreferenceKeys.remindersHabitsSyncEnabled) private var habitsSyncEnabled = false
    @AppStorage(PreferenceKeys.defaultHabitReminderCalendarID) private var defaultHabitListID = ""

    @State private var lists: [ReminderListDTO] = []
    @State private var selectedIDs: Set<String> = []
    @State private var selectedHabitIDs: Set<String> = []
    @State private var isLoadingLists = false

    var body: some View {
        Section("Apple Reminders") {
            Toggle("Sync with Reminders", isOn: $syncEnabled)
                .onChange(of: syncEnabled) { _, enabled in
                    if enabled {
                        // Await access before refresh so authorized UI appears without off→on.
                        Task { await enableSync() }
                    } else {
                        persistSelection()
                        appState.invalidateRemindersSync()
                        appState.refresh()
                    }
                }

            if syncEnabled {
                accessStatusRow

                if appState.remindersAccessStatus == .authorized {
                    if isLoadingLists {
                        ProgressView().controlSize(.small)
                    } else if lists.isEmpty {
                        Text("No reminder lists found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(lists) { list in
                            Toggle(list.title, isOn: binding(for: list.calendarIdentifier))
                        }
                    }

                    Toggle("Include items without a due date", isOn: $includeUndated)
                        .onChange(of: includeUndated) { _, _ in
                            appState.invalidateRemindersSync()
                            appState.refresh()
                        }

                    Toggle("Also add new tasks to Reminders", isOn: $pushNewTodos)
                        .onChange(of: pushNewTodos) { _, _ in
                            appState.refresh()
                        }

                    if pushNewTodos, !lists.isEmpty {
                        Picker("Default list", selection: $defaultListID) {
                            Text("First selected list").tag("")
                            ForEach(lists) { list in
                                Text(list.title).tag(list.calendarIdentifier)
                            }
                        }
                    }

                    if let synced = appState.remindersLastSyncedAt {
                        Text("Last synced \(synced.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = appState.remindersLastSyncError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Text("Dropping a synced task marks it completed in Reminders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    habitSyncSection

                    HStack {
                        Button("Sync now") {
                            appState.invalidateRemindersSync()
                            appState.refresh()
                        }
                        .disabled(appState.isRemindersSyncing)

                        if appState.isRemindersSyncing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .onAppear {
            selectedIDs = Set(Preferences.selectedReminderCalendarIDs)
            selectedHabitIDs = Set(Preferences.selectedHabitReminderCalendarIDs)
            appState.refreshRemindersAccessStatus()
            if syncEnabled { Task { await loadLists() } }
        }
    }

    @ViewBuilder
    private var habitSyncSection: some View {
        Toggle("Sync habits to Reminders", isOn: $habitsSyncEnabled)
            .onChange(of: habitsSyncEnabled) { _, _ in
                appState.invalidateRemindersSync()
                appState.refresh()
            }

        if habitsSyncEnabled, !lists.isEmpty {
            Text("Habit lists (empty uses task lists above)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(lists) { list in
                Toggle(list.title, isOn: habitBinding(for: list.calendarIdentifier))
            }
            Picker("Default habit list", selection: $defaultHabitListID) {
                Text("First selected list").tag("")
                ForEach(lists) { list in
                    Text(list.title).tag(list.calendarIdentifier)
                }
            }
            Text("Each synced habit becomes a recurring reminder. Skipping a habit in DayBar won't update Reminders.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var accessStatusRow: some View {
        switch appState.remindersAccessStatus {
        case .authorized:
            EmptyView()
        case .notDetermined:
            Button("Grant Reminders access…") {
                Task { await enableSync() }
            }
        case .denied, .restricted:
            Text("Reminders access denied. Enable it in System Settings → Privacy & Security → Reminders.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { on in
                if on { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
                persistSelection()
                appState.invalidateRemindersSync()
                appState.refresh()
            }
        )
    }

    private func habitBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedHabitIDs.contains(id) },
            set: { on in
                if on { selectedHabitIDs.insert(id) } else { selectedHabitIDs.remove(id) }
                persistHabitSelection()
                appState.invalidateRemindersSync()
                appState.refresh()
            }
        )
    }

    private func persistSelection() {
        UserDefaults.standard.set(Array(selectedIDs), forKey: PreferenceKeys.selectedReminderCalendarIDs)
    }

    private func persistHabitSelection() {
        UserDefaults.standard.set(Array(selectedHabitIDs), forKey: PreferenceKeys.selectedHabitReminderCalendarIDs)
    }

    private func enableSync() async {
        _ = await appState.requestRemindersAccess()
        await loadLists()
        appState.invalidateRemindersSync()
        appState.refresh()
    }

    private func loadLists() async {
        isLoadingLists = true
        lists = await appState.remindersSync.fetchLists()
        if selectedIDs.isEmpty, let first = lists.first {
            selectedIDs = [first.calendarIdentifier]
            persistSelection()
        }
        isLoadingLists = false
    }
}
