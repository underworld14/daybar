import SwiftUI
import KeyboardShortcuts
import DayBarCore

/// In-panel settings sheet: Pomodoro durations, the timer-end sound, and launch-at-login.
/// Bindings use `@AppStorage` over the same keys `Preferences` reads; Pomodoro changes are
/// pushed into the running engine via `appState.applyPreferences()`.
struct SettingsView: View {
    var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @AppStorage(PreferenceKeys.workMinutes) private var workMinutes = 25
    @AppStorage(PreferenceKeys.shortBreakMinutes) private var shortBreakMinutes = 5
    @AppStorage(PreferenceKeys.longBreakMinutes) private var longBreakMinutes = 15
    @AppStorage(PreferenceKeys.cyclesBeforeLongBreak) private var cycles = 4
    @AppStorage(PreferenceKeys.autoStartNext) private var autoStart = false
    @AppStorage(PreferenceKeys.skipBreakWhenIdle) private var skipBreakWhenIdle = true
    @AppStorage(PreferenceKeys.idleSkipMinutes) private var idleSkipMinutes = 45
    @AppStorage(PreferenceKeys.soundEnabled) private var soundEnabled = true
    @AppStorage(PreferenceKeys.soundName) private var soundName = "Glass"

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

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private var pomodoroSnapshot: String {
        "\(workMinutes)-\(shortBreakMinutes)-\(longBreakMinutes)-\(cycles)-\(autoStart)"
    }

    private var notifSnapshot: String {
        "\(morningEnabled):\(morningHour):\(morningMinute)-\(eveningEnabled):\(eveningHour):\(eveningMinute)-\(habitNotifyEnabled)"
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
                    Text("If you forget to start a break and step away, DayBar assumes you rested and starts the next focus session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Sound") {
                    Toggle("Play a sound when a timer ends", isOn: $soundEnabled)
                    Picker("Sound", selection: $soundName) {
                        ForEach(Preferences.availableSounds, id: \.self) { Text($0).tag($0) }
                    }
                    .disabled(!soundEnabled)
                    Button("Test sound") { AppKitBridge.playPhaseEndSound(named: soundName) }
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
                }

                HabitsSettingsSection(appState: appState)
                RemindersSettingsSection(appState: appState)

                Section("Lofi Radio") {
                    Toggle("Pause music when focus session ends", isOn: $radioPauseOnFocusEnd)
                }

                Section("Startup") {
                    Toggle("Launch DayBar at login", isOn: $launchAtLogin)
                    if LaunchAtLogin.requiresApproval {
                        Button("Open Login Items in System Settings") { LaunchAtLogin.openSystemSettings() }
                    }
                }

                Section("Shortcut") {
                    KeyboardShortcuts.Recorder("Quick-add task", name: .quickAdd)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 380, height: 680)
        .onChange(of: pomodoroSnapshot) { _, _ in appState.applyPreferences() }
        .onChange(of: notifSnapshot) { _, _ in
            appState.invalidateHabitNotifications()
            appState.notifications.rescheduleRepeating()
            appState.refresh()
        }
        .onChange(of: launchAtLogin) { _, newValue in
            try? LaunchAtLogin.setEnabled(newValue)
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
