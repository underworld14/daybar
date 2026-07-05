import SwiftUI
import DayBarCore

/// Browse completed tasks grouped by day (last 30 days).
struct TaskHistoryView: View {
    var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var groups: [DayHistoryGroup] { appState.completedHistory() }
    private var total: Int { groups.reduce(0) { $0 + $1.count } }
    private var dayCount: Int { max(1, groups.count) }
    private var averagePerDay: Int { total / dayCount }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Task History").font(.system(.headline, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups) { group in
                            daySection(group)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 360, height: 520)
    }

    private var summary: some View {
        HStack(spacing: 16) {
            summaryItem(value: "\(total)", label: "completed")
            summaryItem(value: "\(averagePerDay)", label: "avg / day")
            summaryItem(value: "30", label: "days")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryItem(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        Text("No completed tasks in the last 30 days.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    private func daySection(_ group: DayHistoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(group.count) done")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(group.todos) { todo in
                HistoryTodoRow(appState: appState, todo: todo)
            }
        }
    }
}

private struct HistoryTodoRow: View {
    var appState: AppState
    let todo: DailyTodo

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(priorityColor)
                .frame(width: 6, height: 6)
            Text(todo.title)
                .lineLimit(2)
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            if let completed = todo.completedDate {
                Text(completed, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contextMenu {
            Button("Bring to today") { appState.reschedule(todo) }
        }
    }

    private var priorityColor: Color {
        switch todo.priority {
        case .high: return .orange
        case .medium: return .secondary.opacity(0.5)
        case .low: return .secondary.opacity(0.3)
        }
    }
}
