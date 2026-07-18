import SwiftUI
import DayBarCore

/// Habit template CRUD inside Settings.
struct HabitsSettingsSection: View {
    var appState: AppState
    @State private var templates: [HabitTemplate] = []
    @State private var archivedTemplates: [HabitTemplate] = []
    @State private var editing: HabitTemplate?
    @State private var showingAdd = false

    var body: some View {
        Section("Habits") {
            if templates.isEmpty {
                Text("No habits yet. Add a daily ritual like “Read after morning coffee”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(templates, id: \.id) { template in
                    Button {
                        editing = template
                    } label: {
                        HStack {
                            Image(systemName: template.symbolName)
                                .foregroundStyle(.tint)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.title)
                                HStack(spacing: 4) {
                                    if !template.cueText.isEmpty {
                                        Text(template.cueText)
                                    }
                                    Text(HabitSchedule.displayLabel(for: template))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if template.remindersSyncEnabled, template.externalReminderIdentifier != nil {
                                Image(systemName: "list.bullet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if template.notifyEnabled {
                                Image(systemName: "bell.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if !archivedTemplates.isEmpty {
                DisclosureGroup("Archived habits") {
                    ForEach(archivedTemplates, id: \.id) { template in
                        HStack {
                            Label(template.title, systemImage: template.symbolName)
                            Spacer()
                            Button("Restore") {
                                appState.unarchiveHabitTemplate(template)
                                reload()
                            }
                        }
                    }
                }
            }
            Button("Add habit…") { showingAdd = true }
        }
        .onAppear { reload() }
        .sheet(item: $editing) { template in
            HabitEditorSheet(appState: appState, template: template, isNew: false) {
                reload()
            }
        }
        .sheet(isPresented: $showingAdd) {
            HabitEditorSheet(appState: appState, template: nil, isNew: true) {
                reload()
            }
        }
    }

    private func reload() {
        let all = (try? appState.store.allHabitTemplates()) ?? []
        templates = all.filter(\.isActive)
        archivedTemplates = all.filter { !$0.isActive }
    }
}

private struct HabitEditorSheet: View {
    var appState: AppState
    var template: HabitTemplate?
    var isNew: Bool
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var cueText = ""
    @State private var symbolName = "circle"
    @State private var notifyEnabled = false
    @State private var anchorEnabled = false
    @State private var anchorHour = 9
    @State private var anchorMinute = 0
    @State private var schedulePreset: HabitSchedulePreset = .everyDay
    @State private var weekdayMask = HabitSchedule.allDaysMask
    @State private var remindersSyncEnabled = false

    private static let symbols = [
        "circle", "book.fill", "drop.fill", "figure.walk", "moon.stars.fill",
        "sun.max.fill", "heart.fill", "leaf.fill", "hands.sparkles.fill", "text.book.closed.fill",
    ]

    private static let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "New habit" : "Edit habit")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            Divider()

            Form {
                TextField("Title", text: $title)
                TextField("Cue (e.g. After morning coffee)", text: $cueText)
                Picker("Icon", selection: $symbolName) {
                    ForEach(Self.symbols, id: \.self) { name in
                        Label(name, systemImage: name).tag(name)
                    }
                }
                Picker("Schedule", selection: $schedulePreset) {
                    Text("Every day").tag(HabitSchedulePreset.everyDay)
                    Text("Weekdays").tag(HabitSchedulePreset.weekdays)
                    Text("Weekends").tag(HabitSchedulePreset.weekends)
                    Text("Custom").tag(HabitSchedulePreset.custom)
                }
                if schedulePreset == .custom {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { index in
                            let selected = (weekdayMask & (1 << index)) != 0
                            Button(Self.weekdayLabels[index]) {
                                if selected {
                                    weekdayMask &= ~(1 << index)
                                } else {
                                    weekdayMask |= (1 << index)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(selected ? .accentColor : .secondary)
                            .accessibilityLabel(Self.weekdayNames[index])
                            .accessibilityValue(selected ? "Selected" : "Not selected")
                        }
                    }
                }
                if Preferences.remindersHabitsSyncEnabled,
                   appState.remindersAccessStatus == .authorized {
                    Toggle("Sync to Reminders", isOn: $remindersSyncEnabled)
                }
                Toggle("Anchor reminder", isOn: $notifyEnabled)
                if notifyEnabled {
                    Toggle("Set reminder time", isOn: $anchorEnabled)
                    if anchorEnabled {
                        DatePicker(
                            "Time",
                            selection: timeBinding,
                            displayedComponents: .hourAndMinute
                        )
                    } else {
                        Text("Turn on a reminder time, or notifications won't fire.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if !isNew, let template {
                    Button("Archive habit", role: .destructive) {
                        appState.archiveHabitTemplate(template)
                        onSave()
                        dismiss()
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 520)
        .onAppear { load() }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: anchorHour, minute: anchorMinute, second: 0, of: Date()
                ) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                anchorHour = c.hour ?? anchorHour
                anchorMinute = c.minute ?? anchorMinute
            }
        )
    }

    private func load() {
        if let template {
            title = template.title
            cueText = template.cueText
            symbolName = template.symbolName
            notifyEnabled = template.notifyEnabled
            schedulePreset = template.schedulePreset
            weekdayMask = template.scheduleWeekdayMask
            remindersSyncEnabled = template.remindersSyncEnabled
            if let hour = template.anchorHour, let minute = template.anchorMinute {
                anchorEnabled = true
                anchorHour = hour
                anchorMinute = minute
            }
        } else if isNew {
            // Global habit sync on → new habits opt in by default; user can still toggle off.
            remindersSyncEnabled = Preferences.remindersHabitsSyncEnabled
        }
    }

    private func save() {
        let hour = (notifyEnabled && anchorEnabled) ? anchorHour : nil
        let minute = (notifyEnabled && anchorEnabled) ? anchorMinute : nil
        let mask = schedulePreset == .custom ? weekdayMask : HabitSchedule.maskForPreset(schedulePreset)
        if isNew {
            _ = appState.addHabitTemplate(
                title: title,
                cueText: cueText,
                symbolName: symbolName,
                anchorHour: hour,
                anchorMinute: minute,
                notifyEnabled: notifyEnabled,
                schedulePreset: schedulePreset,
                scheduleWeekdayMask: mask,
                remindersSyncEnabled: remindersSyncEnabled
            )
        } else if let template {
            template.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            template.cueText = cueText.trimmingCharacters(in: .whitespacesAndNewlines)
            template.symbolName = symbolName
            template.notifyEnabled = notifyEnabled
            template.anchorHour = hour
            template.anchorMinute = minute
            template.schedulePresetRaw = schedulePreset.rawValue
            template.scheduleWeekdayMask = mask
            template.remindersSyncEnabled = remindersSyncEnabled
            appState.updateHabitTemplate(template)
            appState.invalidateHabitNotifications()
        }
        onSave()
        dismiss()
    }
}