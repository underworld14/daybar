import SwiftUI
import AppKit
import KeyboardShortcuts
import DayBarCore

/// In-panel settings sheet: Pomodoro durations, the timer-end sound, and launch-at-login.
/// Bindings use `@AppStorage` over the same keys `Preferences` reads; Pomodoro changes are
/// pushed into the running engine via `appState.applyPreferences()`.
struct SettingsView: View {
    var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(PreferenceKeys.workMinutes) private var workMinutes = 25
    @AppStorage(PreferenceKeys.shortBreakMinutes) private var shortBreakMinutes = 5
    @AppStorage(PreferenceKeys.longBreakMinutes) private var longBreakMinutes = 15
    @AppStorage(PreferenceKeys.cyclesBeforeLongBreak) private var cycles = 4
    @AppStorage(PreferenceKeys.autoStartNext) private var autoStart = false
    @AppStorage(PreferenceKeys.skipBreakWhenIdle) private var skipBreakWhenIdle = true
    @AppStorage(PreferenceKeys.idleSkipMinutes) private var idleSkipMinutes = 45
    @AppStorage(PreferenceKeys.soundEnabled) private var soundEnabled = true
    @AppStorage(PreferenceKeys.tickingSoundEnabled) private var tickingSoundEnabled = false
    @AppStorage(PreferenceKeys.gardenSoundEnabled) private var gardenSoundEnabled = true
    @AppStorage(PreferenceKeys.gardenActionMode) private var gardenActionMode: GardenActionMode = .automatic

    @AppStorage(PreferenceKeys.morningEnabled) private var morningEnabled = true
    @AppStorage(PreferenceKeys.morningHour) private var morningHour = 9
    @AppStorage(PreferenceKeys.morningMinute) private var morningMinute = 0
    @AppStorage(PreferenceKeys.eveningEnabled) private var eveningEnabled = true
    @AppStorage(PreferenceKeys.eveningHour) private var eveningHour = 18
    @AppStorage(PreferenceKeys.eveningMinute) private var eveningMinute = 0
    @AppStorage(PreferenceKeys.phaseEndNotify) private var phaseEndNotify = true
    @AppStorage(PreferenceKeys.backlogNotify) private var backlogNotify = true
    @AppStorage(PreferenceKeys.habitNotifyEnabled) private var habitNotifyEnabled = true
    @AppStorage(PreferenceKeys.radioPauseOnFocusEnd) private var radioPauseOnFocusEnd = true
    @AppStorage(PreferenceKeys.moodAIEnabled) private var moodAIEnabled = true
    @AppStorage(PreferenceKeys.escalationIntensity) private var escalationIntensity = 0
    @AppStorage(PreferenceKeys.quietHoursEnabled) private var quietHoursEnabled = false
    @AppStorage(PreferenceKeys.quietHoursStartHour) private var quietHoursStartHour = 21
    @AppStorage(PreferenceKeys.respectSystemFocus) private var respectSystemFocus = true
    @AppStorage(PreferenceKeys.weeklyDigestEnabled) private var weeklyDigestEnabled = false
    @State private var awayEnabled = Preferences.awayStartDate != nil
    @State private var awayStart = Preferences.awayStartDate ?? Date()
    @State private var awayEnd = Preferences.awayEndDate ?? Date()

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginMessage: String?
    @State private var dataMessage: String?
    @State private var pendingRestoreURL: URL?
    @State private var showRestoreConfirmation = false

    private var pomodoroSnapshot: String {
        "\(workMinutes)-\(shortBreakMinutes)-\(longBreakMinutes)-\(cycles)-\(autoStart)"
    }

    private var notifSnapshot: String {
        "\(morningEnabled):\(morningHour):\(morningMinute)-\(eveningEnabled):\(eveningHour):\(eveningMinute)-\(phaseEndNotify)-\(backlogNotify)-\(habitNotifyEnabled)"
    }

    private func timeBinding(_ hour: Binding<Int>, _ minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: hour.wrappedValue, minute: minute.wrappedValue, second: 0, of: Date()) ?? Date() },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                hour.wrappedValue = c.hour ?? hour.wrappedValue
                minute.wrappedValue = c.minute ?? minute.wrappedValue
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(.headline, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()

            Form {
                Section("Pomodoro") {
                    Stepper("Focus: \(workMinutes) min", value: $workMinutes, in: 1...120)
                    Stepper("Short break: \(shortBreakMinutes) min", value: $shortBreakMinutes, in: 1...60)
                    Stepper("Long break: \(longBreakMinutes) min", value: $longBreakMinutes, in: 1...60)
                    Stepper("Long break every \(cycles) focus sessions", value: $cycles, in: 1...12)
                    Toggle("Auto-start the next phase", isOn: $autoStart)
                    Toggle("Skip break when away", isOn: $skipBreakWhenIdle)
                    if skipBreakWhenIdle {
                        Stepper("Away threshold: \(idleSkipMinutes) min", value: $idleSkipMinutes, in: 30...60)
                    }
                    Text("If you forget to start a break and step away, DayBar assumes you rested and starts the next focus session. Only applies when the break timer has not been started.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Sound") {
                    Toggle("Play a sound when a timer ends", isOn: $soundEnabled)
                    Button("Test sound") { AlertSoundPlayer.shared.playTestRing() }
                        .disabled(!soundEnabled)
                    Toggle("Play ticking sound during focus", isOn: $tickingSoundEnabled)
                }

                Section("Garden") {
                    Picker("Garden actions", selection: $gardenActionMode) {
                        Text("Automatic").tag(GardenActionMode.automatic)
                        Text("Manual").tag(GardenActionMode.manual)
                    }
                    .onChange(of: gardenActionMode) { _, _ in appState.refresh() }
                    Text(gardenActionMode == .automatic
                         ? "Completed focus sessions plant and harvest for you."
                         : "Completed sessions grow your crops; you harvest ripe plots and plant empty ones in the Garden tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Play garden growth sounds", isOn: $gardenSoundEnabled)
                        .disabled(!soundEnabled)
                }

                Section("Notifications") {
                    Toggle("Morning planning reminder", isOn: $morningEnabled)
                    DatePicker("Morning time", selection: timeBinding($morningHour, $morningMinute), displayedComponents: .hourAndMinute)
                        .disabled(!morningEnabled)
                    Toggle("Evening review reminder", isOn: $eveningEnabled)
                    DatePicker("Evening time", selection: timeBinding($eveningHour, $eveningMinute), displayedComponents: .hourAndMinute)
                        .disabled(!eveningEnabled)
                    Toggle("Notify when a Pomodoro phase ends", isOn: $phaseEndNotify)
                    Toggle("Remind me about piled-up tasks", isOn: $backlogNotify)
                    Toggle("Habit anchor reminders", isOn: $habitNotifyEnabled)
                    if !appState.notifications.authorized {
                        notificationPermissionRow
                    }
                }

                HabitsSettingsSection(appState: appState)
                RemindersSettingsSection(appState: appState)

                Section("Lofi Radio") {
                    Toggle("Pause music when focus session ends", isOn: $radioPauseOnFocusEnd)
                }

                moodSection

                Section("Calm & Away") {
                    Picker("Nudge intensity", selection: $escalationIntensity) {
                        Text("Gentle").tag(0)
                        Text("Standard").tag(1)
                    }
                    .onChange(of: escalationIntensity) { _, _ in appState.applyPreferences() }
                    Toggle("Quiet hours (soften sounds)", isOn: $quietHoursEnabled)
                    if quietHoursEnabled {
                        Stepper("Quiet from \(quietHoursStartHour):00", value: $quietHoursStartHour, in: 18...23)
                    }
                    Toggle("Respect system Focus / Do Not Disturb", isOn: $respectSystemFocus)
                    Toggle("Weekly Sunday digest", isOn: $weeklyDigestEnabled)
                    Toggle("Away mode", isOn: $awayEnabled)
                    if awayEnabled {
                        DatePicker("Away from", selection: $awayStart, displayedComponents: .date)
                        DatePicker("Away until", selection: $awayEnd, displayedComponents: .date)
                    }
                    Text("Away days pause habit materialization and hide aging badges.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                dataSection

                Section("Startup") {
                    Toggle("Launch DayBar at login", isOn: $launchAtLogin)
                    if LaunchAtLogin.requiresApproval {
                        Button("Open Login Items in System Settings") { LaunchAtLogin.openSystemSettings() }
                    }
                    if let launchAtLoginMessage {
                        Text(launchAtLoginMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Updates") {
                    Button("Check for Updates…") {
                        UpdateController.shared.checkForUpdates()
                    }
                    .disabled(!UpdateController.shared.canCheckForUpdates)
                    Text("DayBar checks for updates daily and asks before installing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Shortcut") {
                    KeyboardShortcuts.Recorder("Quick-add task", name: .quickAdd)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 380, height: 720)
        .alert("Restore backup?", isPresented: $showRestoreConfirmation) {
            Button("Cancel", role: .cancel) { pendingRestoreURL = nil }
            Button("Restore", role: .destructive) {
                if let pendingRestoreURL { restoreData(from: pendingRestoreURL) }
                pendingRestoreURL = nil
            }
        } message: {
            Text("This replaces local tasks and habits. Focus sessions are replaced only if the backup includes them (older backups leave focus history alone).")
        }
        .onAppear {
            refreshExternalStatus()
        }
        .onChange(of: pomodoroSnapshot) { _, _ in appState.applyPreferences() }
        .onChange(of: tickingSoundEnabled) { _, _ in appState.syncTickingSound() }
        .onChange(of: notifSnapshot) { _, _ in
            appState.invalidateHabitNotifications()
            appState.notifications.rescheduleRepeating()
            appState.refresh()
        }
        .onChange(of: launchAtLogin) { _, newValue in
            do {
                try LaunchAtLogin.setEnabled(newValue)
                launchAtLoginMessage = nil
            } catch {
                launchAtLoginMessage = error.localizedDescription
            }
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshExternalStatus() }
        }
        .onChange(of: awayEnabled) { _, enabled in
            if enabled {
                Preferences.awayStartDate = Calendar.current.startOfDay(for: awayStart)
                Preferences.awayEndDate = Calendar.current.startOfDay(for: awayEnd)
            } else {
                Preferences.awayStartDate = nil
                Preferences.awayEndDate = nil
            }
            appState.refresh()
        }
        .onChange(of: awayStart) { _, value in
            guard awayEnabled else { return }
            Preferences.awayStartDate = Calendar.current.startOfDay(for: value)
            appState.refresh()
        }
        .onChange(of: awayEnd) { _, value in
            guard awayEnabled else { return }
            Preferences.awayEndDate = Calendar.current.startOfDay(for: value)
            appState.refresh()
        }
    }

    // MARK: - Notifications

    private var notificationPermissionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notifications are turned off for DayBar, so reminders and phase-end banners won't appear.")
                .font(.caption).foregroundStyle(.orange)
            Button("Open System Settings") { AppKitBridge.openNotificationSettings() }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section("Data") {
            HStack {
                Button("Back Up…") { backUpData() }
                Button("Restore…") { chooseRestoreFile() }
            }
            Text("Backs up tasks, habits, and focus sessions (not mood reflections yet).")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let saved = appState.store.lastSuccessfulSaveAt {
                Text("Local data last saved \(saved.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Local data has not been saved this session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let dataMessage {
                Text(dataMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refreshExternalStatus() {
        appState.notifications.refreshAuthorizationStatus()
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func backUpData() {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        panel.nameFieldStringValue = "daybar-backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONStore.encode(appState.store.exportSnapshot())
            try data.write(to: url, options: .atomic)
            dataMessage = "Backup saved to \(url.lastPathComponent)."
        } catch {
            dataMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func chooseRestoreFile() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingRestoreURL = url
        showRestoreConfirmation = true
    }

    private func restoreData(from url: URL) {
        do {
            let snapshot = try JSONStore.decode(try Data(contentsOf: url))
            if appState.store.importSnapshot(snapshot) {
                appState.refresh()
                dataMessage = "Restored \(url.lastPathComponent)."
            } else {
                dataMessage = appState.store.lastSaveError ?? "Restore failed."
            }
        } catch {
            dataMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Mood

    @ViewBuilder
    private var moodSection: some View {
        Section("Mood") {
            Toggle("Suggest mood with Apple Intelligence", isOn: $moodAIEnabled)
            Text("Off, unsupported, or unavailable always falls back to the manual emoji picker in the end-of-day review — mood tracking works fully either way.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if moodAIEnabled {
                moodAvailabilityRow
            }
        }
    }

    @ViewBuilder
    private var moodAvailabilityRow: some View {
        switch appState.moodChecker.availability {
        case .available:
            EmptyView()
        case .unavailable(.appleIntelligenceNotEnabled):
            Text("Apple Intelligence is turned off.")
                .font(.caption).foregroundStyle(.orange)
            Button("Open System Settings") { AppKitBridge.openAppleIntelligenceSettings() }
        case .unavailable(.deviceNotEligible):
            Text("This Mac isn't eligible for Apple Intelligence. The emoji picker still works fully.")
                .font(.caption).foregroundStyle(.secondary)
        case .unavailable(.osTooOld):
            Text("Requires macOS 26 or later. The emoji picker still works fully.")
                .font(.caption).foregroundStyle(.secondary)
        case .unavailable(.modelNotReady):
            Text("The on-device model is still preparing — try again shortly.")
                .font(.caption).foregroundStyle(.secondary)
        case .unavailable(.other):
            EmptyView()
        }
    }
}
