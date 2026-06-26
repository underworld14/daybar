import SwiftUI
import DayBarCore

/// The end-of-day ritual: "Did you finish what you planned?" — triage each unfinished task
/// and jot a one-line reflection. Saving writes today's `DayLog` (which also marks the day
/// reviewed, so the auto-prompt won't fire again).
struct EndOfDayReviewView: View {
    var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var reflection = ""

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
                }
                .padding()
            }

            Divider()
            HStack {
                Spacer()
                Button("Finish review") {
                    appState.saveDayLog(reflection: reflection)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 520)
        .onAppear {
            reflection = ((try? appState.store.dayLog(for: .now)) ?? nil)?.reflection ?? ""
        }
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
