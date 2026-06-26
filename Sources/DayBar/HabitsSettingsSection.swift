import SwiftUI
import DayBarCore

/// Habit template CRUD inside Settings.
struct HabitsSettingsSection: View {
    var appState: AppState
    @State private var templates: [HabitTemplate] = []
    @State private var editing: HabitTemplate?
    @State private var showingAdd = false

    var body: some View {
        Section("Habits") {
            if templates.isEmpty {
                Text("No habits yet. Add a daily ritual like “Read after Dhuha”.")
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
                                if !template.cueText.isEmpty {
                                    Text(template.cueText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
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
        templates = (try? appState.store.allHabitTemplates().filter(\.isActive)) ?? []
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

    private static let symbols = [
        "circle", "book.fill", "drop.fill", "figure.walk", "moon.stars.fill",
        "sun.max.fill", "heart.fill", "leaf.fill", "hands.sparkles.fill", "text.book.closed.fill",
    ]

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
                TextField("Cue (e.g. After Dhuha prayer)", text: $cueText)
                Picker("Icon", selection: $symbolName) {
                    ForEach(Self.symbols, id: \.self) { name in
                        Label(name, systemImage: name).tag(name)
                    }
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
        .frame(width: 360, height: 420)
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
        guard let template else { return }
        title = template.title
        cueText = template.cueText
        symbolName = template.symbolName
        notifyEnabled = template.notifyEnabled
        if let hour = template.anchorHour, let minute = template.anchorMinute {
            anchorEnabled = true
            anchorHour = hour
            anchorMinute = minute
        }
    }

    private func save() {
        let hour = (notifyEnabled && anchorEnabled) ? anchorHour : nil
        let minute = (notifyEnabled && anchorEnabled) ? anchorMinute : nil
        if isNew {
            _ = appState.addHabitTemplate(
                title: title,
                cueText: cueText,
                symbolName: symbolName,
                anchorHour: hour,
                anchorMinute: minute,
                notifyEnabled: notifyEnabled
            )
        } else if let template {
            template.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            template.cueText = cueText.trimmingCharacters(in: .whitespacesAndNewlines)
            template.symbolName = symbolName
            template.notifyEnabled = notifyEnabled
            template.anchorHour = hour
            template.anchorMinute = minute
            appState.updateHabitTemplate(template)
        }
        onSave()
        dismiss()
    }
}