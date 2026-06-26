import SwiftUI
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
    @AppStorage(PreferenceKeys.soundEnabled) private var soundEnabled = true
    @AppStorage(PreferenceKeys.soundName) private var soundName = "Glass"

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private var pomodoroSnapshot: String {
        "\(workMinutes)-\(shortBreakMinutes)-\(longBreakMinutes)-\(cycles)-\(autoStart)"
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

                Section("Startup") {
                    Toggle("Launch DayBar at login", isOn: $launchAtLogin)
                    if LaunchAtLogin.requiresApproval {
                        Button("Open Login Items in System Settings") { LaunchAtLogin.openSystemSettings() }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 380, height: 500)
        .onChange(of: pomodoroSnapshot) { _, _ in appState.applyPreferences() }
        .onChange(of: launchAtLogin) { _, newValue in
            try? LaunchAtLogin.setEnabled(newValue)
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
