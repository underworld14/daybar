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
    /// Reflection text when the user last tapped a mood chip — manual picks only stick for
    /// that exact text; editing the reflection allows a fresh AI suggestion.
    @State private var reflectionAtManualPick: String?
    /// True when reopened (e.g. via "Review day…") after already finishing today's review.
    @State private var isExistingReview = false
    /// Reflection loaded on appear — used to allow auto re-classify when the user edits it.
    @State private var savedReflectionOnOpen = ""
    /// Bumps to re-run classification on demand (reopened reviews).
    @State private var forceSuggestToken = 0
    @State private var isAnalyzingMood = false
    /// Bumps on each classification attempt so stale tasks cannot clear the spinner.
    @State private var moodAnalysisGeneration = 0

    private var unfinished: [DailyTodo] {
        appState.todayTodos.filter { !$0.isCompleted } + appState.carriedTodos
    }

    private var openHabits: [TodayHabit] {
        appState.todayHabits.filter { !$0.log.isCompleted }
    }

    private var moodSuggestionTaskID: String {
        "\(reflection)#\(forceSuggestToken)"
    }

    private var canSuggestMoodWithAI: Bool {
        Preferences.moodAIEnabled && appState.moodChecker.availability == .available
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
                                .accessibilityLabel("Mark \(habit.template.title) complete")
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
            savedReflectionOnOpen = reflection
            selectedMood = existing?.moodTag
            moodSource = existing?.moodSource ?? .none
            isExistingReview = existing != nil
            if existing?.moodSource == .manual {
                reflectionAtManualPick = existing?.reflection
            }
        }
        .task(id: moodSuggestionTaskID) {
            let explicit = forceSuggestToken > 0
            moodAnalysisGeneration += 1
            let generation = moodAnalysisGeneration
            await suggestMoodIfEligible(explicitRequest: explicit, generation: generation)
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
            moodFooter
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var moodFooter: some View {
        if isAnalyzingMood {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Analyzing your reflection…")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Analyzing your reflection for a mood suggestion")
        } else if selectedMood != nil, moodSource == .ai {
            Text("Suggested by Apple Intelligence — tap to correct.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if selectedMood != nil, moodSource == .heuristic {
            Text("Suggested from keywords in your reflection — tap to correct.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if selectedMood != nil, moodSource == .manual {
            Text(manualMoodFooterText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if canShowResuggestButton {
            Button("Suggest mood again") {
                reflectionAtManualPick = nil
                forceSuggestToken += 1
            }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isAnalyzingMood)
        }
    }

    private var canShowResuggestButton: Bool {
        canSuggestMoodWithAI
            && isExistingReview
            && MoodAIGate.hasEnoughTextForClassification(reflection)
    }

    private var manualMoodFooterText: String {
        if canShowResuggestButton {
            return "You picked this mood — tap Suggest mood again or edit your reflection."
        }
        return "You picked this mood — edit your reflection for a new suggestion."
    }

    private func moodButton(_ tag: MoodTag) -> some View {
        let isSelected = selectedMood == tag
        return Button {
            if isSelected {
                selectedMood = nil
                moodSource = .none
                reflectionAtManualPick = nil
            } else {
                selectedMood = tag
                moodSource = .manual
                reflectionAtManualPick = reflection
            }
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
        .accessibilityLabel(isSelected ? "Clear mood selection" : "Select \(tag.displayName) mood")
    }

    /// Debounced AI auto-suggest: `.task(id:)` cancels the previous attempt whenever the
    /// reflection changes (or the user taps "Suggest mood again").
    private func suggestMoodIfEligible(explicitRequest: Bool = false, generation: Int) async {
        let text = reflection
        let eligible = MoodAIGate.shouldAttemptClassification(
            availability: appState.moodChecker.availability,
            aiEnabled: Preferences.moodAIEnabled,
            reflection: text,
            alreadyReviewed: isExistingReview,
            savedReflection: savedReflectionOnOpen,
            explicitRequest: explicitRequest
        )
        guard eligible else {
            setAnalyzingMood(false, generation: generation)
            return
        }

        setAnalyzingMood(true, generation: generation)
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }

        guard #available(macOS 26.0, *) else {
            setAnalyzingMood(false, generation: generation)
            return
        }
        guard let result = await classifyMood(text) else {
            setAnalyzingMood(false, generation: generation)
            return
        }
        guard MoodAIGate.shouldApplySuggestion(
            isCancelled: Task.isCancelled,
            currentSource: moodSource,
            reflectionAtManualPick: reflectionAtManualPick,
            classifiedReflection: text,
            explicitRequest: explicitRequest
        ) else {
            setAnalyzingMood(false, generation: generation)
            return
        }

        selectedMood = result.tag
        moodSource = result.source
        reflectionAtManualPick = nil
        setAnalyzingMood(false, generation: generation)
    }

    private func setAnalyzingMood(_ value: Bool, generation: Int) {
        guard generation == moodAnalysisGeneration else { return }
        isAnalyzingMood = value
    }

    private func reviewRow(_ todo: DailyTodo) -> some View {
        HStack(spacing: 8) {
            Button { appState.toggleComplete(todo) } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isCompleted ? "Mark \(todo.title) incomplete" : "Mark \(todo.title) complete")

            Text(todo.title).lineLimit(1)

            if let age = todo.ageLabel() {
                AgePill(text: age, tier: todo.escalationTier(thresholds: appState.thresholds))
            }

            Spacer(minLength: 6)

            Button("Tomorrow") { appState.delay(todo) }
                .buttonStyle(.bordered).controlSize(.small)
                .accessibilityLabel("Move \(todo.title) to tomorrow")
            Button("Drop", role: .destructive) { appState.drop(todo) }
                .buttonStyle(.bordered).controlSize(.small)
                .accessibilityLabel("Drop \(todo.title)")
        }
    }
}
