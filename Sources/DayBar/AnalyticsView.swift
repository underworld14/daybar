import SwiftUI
import Charts
import DayBarCore

private enum StatsTab: String, CaseIterable {
    case tasks = "Tasks"
    case habits = "Habits"
}

/// Daily / weekly / monthly analytics for tasks and habits.
struct AnalyticsView: View {
    var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var tab: StatsTab = .tasks
    @State private var granularity: Granularity = .day

    private func count(for g: Granularity) -> Int {
        switch g {
        case .day: return 14
        case .week: return 12
        case .month: return 12
        }
    }

    private var buckets: [StatBucket] {
        appState.statBuckets(granularity: granularity, count: count(for: granularity))
    }

    private var habitBuckets: [HabitStatBucket] {
        appState.habitStatBuckets(granularity: granularity, count: count(for: granularity))
    }

    private var xUnit: Calendar.Component {
        switch granularity {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    private var xDomain: ClosedRange<Date> {
        let source = tab == .tasks ? buckets.first?.date : habitBuckets.first?.date
        let lastSource = tab == .tasks ? buckets.last?.date : habitBuckets.last?.date
        let first = source ?? Date.now
        let last = Analytics.advance(lastSource ?? Date.now, granularity, by: 1)
        return first...last
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Statistics").font(.system(.headline, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("View", selection: $tab) {
                        ForEach(StatsTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Range", selection: $granularity) {
                        Text("Day").tag(Granularity.day)
                        Text("Week").tag(Granularity.week)
                        Text("Month").tag(Granularity.month)
                    }
                    .pickerStyle(.segmented)

                    if tab == .tasks {
                        tasksContent
                    } else {
                        habitsContent
                    }
                }
                .padding()
            }
        }
        .frame(width: 460, height: 640)
    }

    // MARK: - Tasks

    @ViewBuilder
    private var tasksContent: some View {
        tasksSummary
        chartSection("Planned vs completed") { plannedVsCompleted }
        chartSection("Completion rate") { completionRate }
        chartSection("Focus minutes") { focusMinutes }
        chartSection("Pomodoro sessions") { sessionsChart }
    }

    private var tasksSummary: some View {
        let planned = buckets.reduce(0) { $0 + $1.planned }
        let completed = buckets.reduce(0) { $0 + $1.completed }
        let focus = buckets.reduce(0) { $0 + $1.focusMinutes }
        let sessions = buckets.reduce(0) { $0 + $1.sessions }
        let completedMinutes = buckets.reduce(0) { $0 + $1.completedMinutes }
        let rate = planned == 0 ? 0 : Int((Double(completed) / Double(planned) * 100).rounded())
        let avg = sessions == 0 ? 0 : completedMinutes / sessions
        return HStack(spacing: 16) {
            stat("\(rate)%", "completion")
            stat(formatMinutes(focus), "focus")
            stat("\(sessions)", "sessions")
            stat("\(avg)m", "avg/session")
        }
    }

    // MARK: - Habits

    @ViewBuilder
    private var habitsContent: some View {
        habitsSummary
        chartSection("Habit completion rate") { habitCompletionRate }
        chartSection("Habits done") { habitsDoneChart }
        consistencySection
        streakSection
    }

    private var habitsSummary: some View {
        let planned = habitBuckets.reduce(0) { $0 + $1.planned }
        let completed = habitBuckets.reduce(0) { $0 + $1.completed }
        let rate = planned == 0 ? 0 : Int((Double(completed) / Double(planned) * 100).rounded())
        let dayCount = max(1, habitBuckets.filter { $0.planned > 0 }.count)
        let avgPerDay = completed / dayCount
        let longest = appState.habitStreaks().map(\.streak.current).max() ?? 0
        return HStack(spacing: 16) {
            stat("\(rate)%", "habits")
            stat("\(avgPerDay)", "avg/day")
            stat("\(longest)d", "longest")
        }
    }

    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONSISTENCY (28 DAYS)".uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
            ForEach(appState.habitStreaks(), id: \.template.id) { entry in
                HabitHeatmapRow(
                    title: entry.template.title,
                    cells: appState.habitHeatmap(templateId: entry.template.id),
                    currentStreak: entry.streak.current
                )
            }
        }
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STREAKS".uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
            ForEach(appState.habitStreaks(), id: \.template.id) { entry in
                HStack {
                    Text(entry.template.title).lineLimit(1)
                    Spacer()
                    Text("\(entry.streak.current)d")
                        .foregroundStyle(.green)
                    Text("(best \(entry.streak.best)d)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Shared helpers

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        return "\(minutes)m"
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func chartSection<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
            content().frame(height: 150)
        }
    }

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let type: String
        let count: Int
    }

    private var plannedVsCompleted: some View {
        let points = buckets.flatMap {
            [Point(date: $0.date, type: "Planned", count: $0.planned),
             Point(date: $0.date, type: "Completed", count: $0.completed)]
        }
        return Chart(points) { p in
            BarMark(x: .value("Date", p.date, unit: xUnit), y: .value("Count", p.count))
                .foregroundStyle(by: .value("Type", p.type))
                .position(by: .value("Type", p.type))
        }
        .chartForegroundStyleScale(["Planned": Color.secondary.opacity(0.45), "Completed": Color.accentColor])
        .chartXScale(domain: xDomain)
    }

    private var completionRate: some View {
        Chart {
            ForEach(buckets) { b in
                LineMark(x: .value("Date", b.date, unit: xUnit), y: .value("Rate", b.completionRate))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor)
                PointMark(x: .value("Date", b.date, unit: xUnit), y: .value("Rate", b.completionRate))
                    .foregroundStyle(Color.accentColor)
            }
            RuleMark(y: .value("Target", 0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.green.opacity(0.5))
        }
        .chartYScale(domain: 0...1)
        .chartYAxis { AxisMarks(format: FloatingPointFormatStyle<Double>.Percent()) }
        .chartXScale(domain: xDomain)
    }

    private var habitCompletionRate: some View {
        Chart {
            ForEach(habitBuckets) { b in
                LineMark(x: .value("Date", b.date, unit: xUnit), y: .value("Rate", b.completionRate))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.green)
                PointMark(x: .value("Date", b.date, unit: xUnit), y: .value("Rate", b.completionRate))
                    .foregroundStyle(Color.green)
            }
            RuleMark(y: .value("Target", 0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.green.opacity(0.5))
        }
        .chartYScale(domain: 0...1)
        .chartYAxis { AxisMarks(format: FloatingPointFormatStyle<Double>.Percent()) }
        .chartXScale(domain: xDomain)
    }

    private var habitsDoneChart: some View {
        let points = habitBuckets.flatMap {
            [Point(date: $0.date, type: "Planned", count: $0.planned),
             Point(date: $0.date, type: "Done", count: $0.completed)]
        }
        return Chart(points) { p in
            BarMark(x: .value("Date", p.date, unit: xUnit), y: .value("Count", p.count))
                .foregroundStyle(by: .value("Type", p.type))
                .position(by: .value("Type", p.type))
        }
        .chartForegroundStyleScale(["Planned": Color.secondary.opacity(0.45), "Done": Color.green])
        .chartXScale(domain: xDomain)
    }

    private var focusMinutes: some View {
        Chart(buckets) { b in
            BarMark(x: .value("Date", b.date, unit: xUnit), y: .value("Minutes", b.focusMinutes))
                .foregroundStyle(Color.orange.gradient)
        }
        .chartXScale(domain: xDomain)
    }

    private var sessionsChart: some View {
        Chart(buckets) { b in
            BarMark(x: .value("Date", b.date, unit: xUnit), y: .value("Sessions", b.sessions))
                .foregroundStyle(Color.accentColor.gradient)
        }
        .chartXScale(domain: xDomain)
    }
}