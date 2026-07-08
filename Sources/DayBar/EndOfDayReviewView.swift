import SwiftUI
import DayBarCore

/// The end-of-day ritual: "Did you finish what you planned?" — triage each unfinished task
/// and jot a one-line reflection. Saving writes today's `DayLog` (which also marks the day
/// reviewed, so the auto-prompt won't fire again).
struct EndOfDayReviewView: View {
    var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var reflection = ""
    @State private var selectedMood: MoodTag?
    @State private var moodSource: MoodSource = .none
    /// True when reopened (e.g. via "Review day…") after already finishing today's review —
    /// gates out auto re-classification so a saved mood is never silently overwritten.
    @State private var isExistingReview = false

    private var unfinished: [DailyTodo] {
        appState.todayTodos.filter { !$0.isCompleted } + appState.carriedTodos
    }

    private var openHabits: [TodayHabit] {
        appState.todayHabits.filter { !$0.log.isCompleted }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Did you finish what you planned?")
                    .font(.system(.headline, design: .rounded))
                Spacer()
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(appState.completedTodayCount)/\(appState.totalTodayCount) tasks done today")
                        .font(.subheadline).foregroundStyle(.secondary)

                    if appState.totalHabitsTodayCount > 0 {
                        Text("\(appState.completedHabitsTodayCount)/\(appState.totalHabitsTodayCount) habits done today")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    if !openHabits.isEmpty {
                        Text("OPEN HABITS").font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
                        ForEach(openHabits) { habit in
                            HStack(spacing: 8) {
                                Button { appState.toggleHabit(habit.log) } label: {
                                    Image(systemName: "circle").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                Text(habit.template.title).lineLimit(1)
                                Spacer()
                            }
                        }
                    }

                    if unfinished.isEmpty && openHabits.isEmpty {
                        Text("All clear — nice work. 🎉").font(.subheadline)
                    } else if !unfinished.isEmpty {
                        Text("STILL OPEN").font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
                        ForEach(unfinished) { reviewRow($0) }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("REFLECTION").font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
                        TextField("One line about today…", text: $reflection, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                    }
                    .padding(.top, 4)

                    moodSection
                }
                .padding()
            }

            Divider()
            HStack {
                Button("Not now") {
                    appState.snoozeEndOfDayReview()
                    dismiss()
                }
                .foregroundStyle(.secondary)
                Spacer()
                Button("Finish review") {
                    appState.saveDayLog(reflection: reflection, moodTag: selectedMood, moodSource: moodSource)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 600)
        .onAppear {
            let existing = (try? appState.store.dayLog(for: .now)) ?? nil
            reflection = existing?.reflection ?? ""
            selectedMood = existing?.moodTag
            moodSource = existing?.moodSource ?? .none
            isExistingReview = existing != nil
        }
        .task(id: reflection) {
            await suggestMoodIfEligible()
        }
    }

    // MARK: - Mood

    private let moodColumns = Array(repeating: GridItem(.flexible()), count: 4)

    @ViewBuilder
    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MOOD").font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
            LazyVGrid(columns: moodColumns, spacing: 8) {
                ForEach(MoodTag.allCases, id: \.self) { tag in
                    moodButton(tag)
                }
            }
            if selectedMood != nil, moodSource == .ai {
                Text("Suggested by Apple Intelligence — tap to correct.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func moodButton(_ tag: MoodTag) -> some View {
        let isSelected = selectedMood == tag
        return Button {
            selectedMood = tag
            moodSource = .manual
        } label: {
            VStack(spacing: 2) {
                Text(tag.emoji).font(.title2)
                Text(tag.displayName).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// Debounced AI auto-suggest: `.task(id: reflection)` cancels the previous attempt
    /// whenever the text changes, so this doubles as debouncing without a manual timer.
    /// Never overrides a mood the user already picked by hand.
    private func suggestMoodIfEligible() async {
        // Snapshot once: `reflection` is a `@State` var, so re-reading it after the sleep
        // below could race a newer keystroke that hasn't cancelled this task yet.
        let text = reflection
        guard MoodAIGate.shouldAttemptClassification(
            availability: appState.moodChecker.availability,
            aiEnabled: Preferences.moodAIEnabled,
            reflection: text,
            alreadyReviewed: isExistingReview
        ) else { return }

        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }

        guard #available(macOS 26.0, *) else { return }
        guard let suggested = await classifyMoodWithTimeout(text) else { return }
        guard MoodAIGate.shouldApplySuggestion(isCancelled: Task.isCancelled, currentSource: moodSource) else { return }

        selectedMood = suggested
        moodSource = .ai
    }

    private func reviewRow(_ todo: DailyTodo) -> some View {
        HStack(spacing: 8) {
            Button { appState.toggleComplete(todo) } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text(todo.title).lineLimit(1)

            if let age = todo.ageLabel() {
                AgePill(text: age, tier: todo.escalationTier(thresholds: appState.thresholds))
            }

            Spacer(minLength: 6)

            Button("Tomorrow") { appState.delay(todo) }
                .buttonStyle(.bordered).controlSize(.small)
            Button("Drop", role: .destructive) { appState.drop(todo) }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }
}
