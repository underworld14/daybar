import SwiftUI
import Charts
import DayBarCore

private enum StatsTab: String, CaseIterable {
    case tasks = "Tasks"
    case habits = "Habits"
    case mood = "Mood"
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

    private var moodBuckets: [MoodStatBucket] {
        appState.moodStatBuckets(granularity: granularity, count: count(for: granularity))
    }

    private var hasTaskData: Bool {
        buckets.contains { $0.planned > 0 || $0.completed > 0 || $0.focusMinutes > 0 || $0.sessions > 0 }
    }

    private var hasHabitData: Bool {
        habitBuckets.contains { $0.planned > 0 || $0.completed > 0 }
    }

    private var hasMoodData: Bool {
        moodBuckets.contains { $0.loggedDays > 0 }
    }

    private var xUnit: Calendar.Component {
        switch granularity {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    private var xDomain: ClosedRange<Date> {
        let source: Date?
        let lastSource: Date?
        switch tab {
        case .tasks: source = buckets.first?.date; lastSource = buckets.last?.date
        case .habits: source = habitBuckets.first?.date; lastSource = habitBuckets.last?.date
        case .mood: source = moodBuckets.first?.date; lastSource = moodBuckets.last?.date
        }
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

                    switch tab {
                    case .tasks: tasksContent
                    case .habits: habitsContent
                    case .mood: moodContent
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
        focusStreakSection
        if hasTaskData {
            chartSection("Planned vs completed") { plannedVsCompleted }
            chartSection("Completion rate") { completionRate }
            chartSection("Focus minutes") { focusMinutes }
            chartSection("Pomodoro sessions") { sessionsChart }
        } else {
            emptyState("No task data yet. Complete tasks or finish a focus session to populate these charts.")
        }
    }

    private var focusStreakSection: some View {
        let entry = appState.focusStreak()
        let streak = entry?.streak
        return VStack(alignment: .leading, spacing: 8) {
            Text("FOCUS STREAK".uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                stat("\(streak?.current ?? 0)d", "current")
                stat("\(streak?.best ?? 0)d", "best")
                stat("\(streak?.graceRemaining ?? FocusAnalytics.gracePerWeek)", "grace left")
            }
            if let cells = entry?.weekCells, !cells.isEmpty {
                DayscapeStrip(
                    cells: cells,
                    currentStreak: streak?.current ?? 0,
                    graceRemaining: streak?.graceRemaining ?? FocusAnalytics.gracePerWeek
                )
            }
        }
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
        if hasHabitData {
            chartSection("Habit completion rate") { habitCompletionRate }
            chartSection("Habits done") { habitsDoneChart }
            consistencySection
            streakSection
        } else {
            emptyState("No habit data yet. Complete a habit to start building trends.")
        }
    }

    private var habitsSummary: some View {
        let planned = habitBuckets.reduce(0) { $0 + $1.planned }
        let completed = habitBuckets.reduce(0) { $0 + $1.completed }
        let rate = planned == 0 ? 0 : Int((Double(completed) / Double(planned) * 100).rounded())
        let dayCount = max(1, habitBuckets.reduce(0) { $0 + calendarDayCount(in: $1.date) })
        let avgPerDay = Double(completed) / Double(dayCount)
        let avgLabel = avgPerDay == floor(avgPerDay) ? "\(Int(avgPerDay))" : String(format: "%.1f", avgPerDay)
        let longest = appState.habitStreaks().map(\.streak.current).max() ?? 0
        return HStack(spacing: 16) {
            stat("\(rate)%", "habits")
            stat(avgLabel, "avg/day")
            stat("\(longest)d", "longest")
        }
    }

    private var consistencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONSISTENCY (28 DAYS)".uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
            ForEach(appState.habitStreaks()) { entry in
                HabitHeatmapRow(
                    title: entry.template.title,
                    cells: entry.heatmap,
                    currentStreak: entry.streak.current,
                    isArchived: !entry.template.isActive
                )
            }
        }
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STREAKS".uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
            ForEach(appState.habitStreaks()) { entry in
                HStack {
                    Text(entry.template.title)
                        .lineLimit(1)
                        .foregroundStyle(entry.template.isActive ? .primary : .secondary)
                    if !entry.template.isActive {
                        Text("archived")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text("\(entry.streak.current)d")
                        .foregroundStyle(entry.template.isActive ? .green : .secondary)
                    Text("(best \(entry.streak.best)d)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    // MARK: - Mood

    @ViewBuilder
    private var moodContent: some View {
        moodSummary
        if hasMoodData {
            chartSection("Mood trend") { moodTrendChart }
        } else {
            emptyState("No mood entries yet. Finish an end-of-day review to see your trend.")
        }
    }

    private var moodSummary: some View {
        let logged = moodBuckets.reduce(0) { $0 + $1.loggedDays }
        let overallAverage = MoodAnalytics.overallAverageScore(moodBuckets)
        return HStack(spacing: 16) {
            stat(overallAverage.map { String(format: "%.1f", $0) } ?? "—", "avg score")
            stat("\(logged)", "days logged")
        }
    }

    private var moodTrendChart: some View {
        let scoredDates = moodBuckets.compactMap { $0.averageScore != nil ? $0.date : nil }
        return HoverableChart(dates: scoredDates, tooltip: { hovered in
            guard let bucket = moodBuckets.first(where: { $0.date == hovered }),
                  let score = bucket.averageScore else { return [] }
            return [dateLabel(hovered), String(format: "Score %.1f", score)]
        }) { hovered in
            Chart {
                ForEach(moodBuckets) { b in
                    if let score = b.averageScore {
                        LineMark(x: .value("Date", b.date, unit: xUnit), y: .value("Score", score))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Color.pink)
                        PointMark(x: .value("Date", b.date, unit: xUnit), y: .value("Score", score))
                            .foregroundStyle(Color.pink)
                    }
                }
                RuleMark(y: .value("Neutral", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.5))
                hoverRule(at: hovered)
            }
            .chartYScale(domain: -2...2)
            .chartXScale(domain: xDomain)
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
            content()
                .frame(height: 150)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
    }

    private func calendarDayCount(in bucketStart: Date) -> Int {
        let calendar = Calendar.current
        let bucketEnd = Analytics.advance(bucketStart, granularity, by: 1, calendar: calendar)
        return max(1, calendar.dateComponents([.day], from: bucketStart, to: bucketEnd).day ?? 1)
    }

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let type: String
        let count: Int
    }

    private func dateLabel(_ date: Date) -> String {
        switch granularity {
        case .day, .week: return date.formatted(.dateTime.month(.abbreviated).day())
        case .month: return date.formatted(.dateTime.month(.abbreviated).year())
        }
    }

    @ChartContentBuilder
    private func hoverRule(at hovered: Date?) -> some ChartContent {
        if let hovered {
            RuleMark(x: .value("Hover", hovered, unit: xUnit))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(.secondary.opacity(0.4))
        }
    }

    private var plannedVsCompleted: some View {
        let points = buckets.flatMap {
            [Point(date: $0.date, type: "Planned", count: $0.planned),
             Point(date: $0.date, type: "Completed", count: $0.completed)]
        }
        return HoverableChart(dates: buckets.map(\.date), tooltip: { hovered in
            guard let bucket = buckets.first(where: { $0.date == hovered }) else { return [] }
            return [dateLabel(hovered), "Planned \(bucket.planned) · Completed \(bucket.completed)"]
        }) { hovered in
            Chart {
                ForEach(points) { p in
                    BarMark(x: .value("Date", p.date, unit: xUnit), y: .value("Count", p.count))
                        .foregroundStyle(by: .value("Type", p.type))
                        .position(by: .value("Type", p.type))
                }
                hoverRule(at: hovered)
            }
            .chartForegroundStyleScale(["Planned": Color.secondary.opacity(0.45), "Completed": Color.accentColor])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXScale(domain: xDomain)
        }
    }

    private var completionRate: some View {
        HoverableChart(dates: buckets.map(\.date), tooltip: { hovered in
            guard let bucket = buckets.first(where: { $0.date == hovered }) else { return [] }
            return [dateLabel(hovered), "\(Int((bucket.completionRate * 100).rounded()))% completion"]
        }) { hovered in
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
                hoverRule(at: hovered)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis { AxisMarks(format: FloatingPointFormatStyle<Double>.Percent()) }
            .chartXScale(domain: xDomain)
        }
    }

    private var habitCompletionRate: some View {
        HoverableChart(dates: habitBuckets.map(\.date), tooltip: { hovered in
            guard let bucket = habitBuckets.first(where: { $0.date == hovered }) else { return [] }
            return [dateLabel(hovered), "\(Int((bucket.completionRate * 100).rounded()))% habits"]
        }) { hovered in
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
                hoverRule(at: hovered)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis { AxisMarks(format: FloatingPointFormatStyle<Double>.Percent()) }
            .chartXScale(domain: xDomain)
        }
    }

    private var habitsDoneChart: some View {
        let points = habitBuckets.flatMap {
            [Point(date: $0.date, type: "Planned", count: $0.planned),
             Point(date: $0.date, type: "Done", count: $0.completed)]
        }
        return HoverableChart(dates: habitBuckets.map(\.date), tooltip: { hovered in
            guard let bucket = habitBuckets.first(where: { $0.date == hovered }) else { return [] }
            return [dateLabel(hovered), "Planned \(bucket.planned) · Done \(bucket.completed)"]
        }) { hovered in
            Chart {
                ForEach(points) { p in
                    BarMark(x: .value("Date", p.date, unit: xUnit), y: .value("Count", p.count))
                        .foregroundStyle(by: .value("Type", p.type))
                        .position(by: .value("Type", p.type))
                }
                hoverRule(at: hovered)
            }
            .chartForegroundStyleScale(["Planned": Color.secondary.opacity(0.45), "Done": Color.green])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXScale(domain: xDomain)
        }
    }

    private var focusMinutes: some View {
        HoverableChart(dates: buckets.map(\.date), tooltip: { hovered in
            guard let bucket = buckets.first(where: { $0.date == hovered }) else { return [] }
            return [dateLabel(hovered), "\(bucket.focusMinutes)m focus"]
        }) { hovered in
            Chart {
                ForEach(buckets) { b in
                    BarMark(x: .value("Date", b.date, unit: xUnit), y: .value("Minutes", b.focusMinutes))
                        .foregroundStyle(Color.orange.gradient)
                }
                hoverRule(at: hovered)
            }
            .chartXScale(domain: xDomain)
        }
    }

    private var sessionsChart: some View {
        HoverableChart(dates: buckets.map(\.date), tooltip: { hovered in
            guard let bucket = buckets.first(where: { $0.date == hovered }) else { return [] }
            return [dateLabel(hovered), "\(bucket.sessions) sessions"]
        }) { hovered in
            Chart {
                ForEach(buckets) { b in
                    BarMark(x: .value("Date", b.date, unit: xUnit), y: .value("Sessions", b.sessions))
                        .foregroundStyle(Color.accentColor.gradient)
                }
                hoverRule(at: hovered)
            }
            .chartXScale(domain: xDomain)
        }
    }
}