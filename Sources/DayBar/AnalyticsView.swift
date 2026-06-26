import SwiftUI
import Charts
import DayBarCore

/// Daily / weekly / monthly analytics: planned-vs-completed, completion-rate trend, and focus
/// minutes. Read on the fly from the store via `appState.statBuckets`.
struct AnalyticsView: View {
    var appState: AppState
    @Environment(\.dismiss) private var dismiss
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

    private var xUnit: Calendar.Component {
        switch granularity {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    private var xDomain: ClosedRange<Date> {
        let first = buckets.first?.date ?? Date.now
        let last = Analytics.advance(buckets.last?.date ?? Date.now, granularity, by: 1)
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
                    Picker("Range", selection: $granularity) {
                        Text("Day").tag(Granularity.day)
                        Text("Week").tag(Granularity.week)
                        Text("Month").tag(Granularity.month)
                    }
                    .pickerStyle(.segmented)

                    summary
                    chartSection("Planned vs completed") { plannedVsCompleted }
                    chartSection("Completion rate") { completionRate }
                    chartSection("Focus minutes") { focusMinutes }
                }
                .padding()
            }
        }
        .frame(width: 460, height: 580)
    }

    private var summary: some View {
        let planned = buckets.reduce(0) { $0 + $1.planned }
        let completed = buckets.reduce(0) { $0 + $1.completed }
        let focus = buckets.reduce(0) { $0 + $1.focusMinutes }
        let rate = planned == 0 ? 0 : Int((Double(completed) / Double(planned) * 100).rounded())
        return HStack(spacing: 16) {
            stat("\(rate)%", "completion")
            stat("\(completed)/\(planned)", "done")
            stat("\(focus)m", "focus")
        }
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

    private var focusMinutes: some View {
        Chart(buckets) { b in
            BarMark(x: .value("Date", b.date, unit: xUnit), y: .value("Minutes", b.focusMinutes))
                .foregroundStyle(Color.orange.gradient)
        }
        .chartXScale(domain: xDomain)
    }
}
