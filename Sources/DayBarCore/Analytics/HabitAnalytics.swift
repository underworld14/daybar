import Foundation

/// One aggregated period for habit analytics charts.
public struct HabitStatBucket: Sendable, Identifiable {
    public let date: Date
    public var planned: Int
    public var completed: Int

    public var id: Date { date }
    public var completionRate: Double { planned == 0 ? 0 : Double(completed) / Double(planned) }

    public init(date: Date, planned: Int = 0, completed: Int = 0) {
        self.date = date
        self.planned = planned
        self.completed = completed
    }
}

public struct StreakInfo: Sendable {
    public let current: Int
    public let best: Int
    public let graceRemaining: Int

    public init(current: Int, best: Int, graceRemaining: Int) {
        self.current = current
        self.best = best
        self.graceRemaining = graceRemaining
    }
}

public struct HabitHeatmapCell: Sendable, Identifiable {
    public let date: Date
    public let status: HabitDayStatus?
    public let usedGrace: Bool

    public var id: Date { date }

    public init(date: Date, status: HabitDayStatus?, usedGrace: Bool = false) {
        self.date = date
        self.status = status
        self.usedGrace = usedGrace
    }
}

/// Pure habit aggregation: streaks, time buckets, and consistency heatmaps.
public enum HabitAnalytics {
    public static let gracePerWeek = 1
    public static let milestoneDays: [Int] = [7, 30, 100]

    public static func buckets(
        logs: [HabitLog],
        endingAt now: Date = .now,
        count: Int,
        granularity: Granularity,
        calendar: Calendar = .current
    ) -> [HabitStatBucket] {
        let last = Analytics.periodStart(now, granularity, calendar: calendar)
        var starts: [Date] = []
        for i in stride(from: count - 1, through: 0, by: -1) {
            starts.append(Analytics.advance(last, granularity, by: -i, calendar: calendar))
        }
        var map: [Date: HabitStatBucket] = [:]
        for s in starts { map[s] = HabitStatBucket(date: s) }

        func key(for date: Date) -> Date? {
            let s = Analytics.periodStart(date, granularity, calendar: calendar)
            return map[s] != nil ? s : nil
        }

        for log in logs {
            if let s = key(for: log.day) {
                map[s]?.planned += 1
                if log.isCompleted { map[s]?.completed += 1 }
            }
        }
        return starts.compactMap { map[$0] }
    }

    public static func heatmap(
        logs: [HabitLog],
        templateId: UUID,
        days: Int,
        endingAt now: Date = .now,
        calendar: Calendar = .current
    ) -> [HabitHeatmapCell] {
        let today = calendar.startOfDay(for: now)
        let templateLogs = logs.filter { $0.templateId == templateId }
        var byDay: [Date: HabitLog] = [:]
        for log in templateLogs {
            byDay[calendar.startOfDay(for: log.day)] = log
        }

        let graceDays = graceDaysUsed(logs: templateLogs, templateId: templateId, asOf: now, calendar: calendar)

        var cells: [HabitHeatmapCell] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let normalized = calendar.startOfDay(for: day)
            let log = byDay[normalized]
            let status = log?.status
            let usedGrace = graceDays.contains(normalized)
            cells.append(HabitHeatmapCell(date: normalized, status: status, usedGrace: usedGrace))
        }
        return cells
    }

    public static func streakInfo(
        logs: [HabitLog],
        templateId: UUID,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> StreakInfo {
        let templateLogs = logs.filter { $0.templateId == templateId }
        let current = currentStreak(logs: templateLogs, asOf: now, calendar: calendar)
        let best = bestStreak(logs: templateLogs, calendar: calendar)
        let graceUsed = graceDaysUsed(logs: templateLogs, templateId: templateId, asOf: now, calendar: calendar).count
        let graceRemaining = max(0, gracePerWeek - graceUsedInRollingWindow(logs: templateLogs, asOf: now, calendar: calendar))
        return StreakInfo(current: current, best: best, graceRemaining: graceRemaining)
    }

    public static func isMilestone(_ streak: Int) -> Bool {
        milestoneDays.contains(streak)
    }

    // MARK: - Private streak helpers

    private static func currentStreak(
        logs: [HabitLog],
        asOf now: Date,
        calendar: Calendar
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: HabitLog] = [:]
        for log in logs { byDay[calendar.startOfDay(for: log.day)] = log }

        var checkDay = today
        if let todayLog = byDay[today], todayLog.status != .completed {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            checkDay = calendar.startOfDay(for: yesterday)
        }

        var streak = 0
        var graceDates: [Date] = []

        while true {
            guard let log = byDay[checkDay] else { break }
            switch log.status {
            case .completed:
                streak += 1
            case .skipped, .pending:
                if canUseGrace(on: checkDay, graceDates: &graceDates, calendar: calendar) {
                    streak += 1
                } else {
                    return streak
                }
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDay) else { break }
            checkDay = calendar.startOfDay(for: prev)
        }
        return streak
    }

    private static func bestStreak(logs: [HabitLog], calendar: Calendar) -> Int {
        let sorted = logs.sorted { $0.day < $1.day }
        guard !sorted.isEmpty else { return 0 }

        var best = 0
        var current = 0
        var graceDates: [Date] = []
        var previousDay: Date?

        for log in sorted {
            let day = calendar.startOfDay(for: log.day)
            if let prev = previousDay,
               calendar.dateComponents([.day], from: prev, to: day).day ?? 0 > 1 {
                current = 0
                graceDates = []
            }
            previousDay = day

            switch log.status {
            case .completed:
                current += 1
            case .skipped, .pending:
                if canUseGrace(on: day, graceDates: &graceDates, calendar: calendar) {
                    current += 1
                } else {
                    current = 0
                    graceDates = []
                }
            }
            best = max(best, current)
        }
        return best
    }

    private static func canUseGrace(
        on day: Date,
        graceDates: inout [Date],
        calendar: Calendar
    ) -> Bool {
        let windowStart = calendar.date(byAdding: .day, value: -6, to: day) ?? day
        let usedInWindow = graceDates.filter { $0 >= windowStart && $0 <= day }.count
        guard usedInWindow < gracePerWeek else { return false }
        graceDates.append(day)
        return true
    }

    private static func graceDaysUsed(
        logs: [HabitLog],
        templateId: UUID,
        asOf now: Date,
        calendar: Calendar
    ) -> Set<Date> {
        _ = templateId
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: HabitLog] = [:]
        for log in logs { byDay[calendar.startOfDay(for: log.day)] = log }

        var graceDays = Set<Date>()
        var checkDay = today
        if let todayLog = byDay[today], todayLog.status != .completed {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return graceDays }
            checkDay = calendar.startOfDay(for: yesterday)
        }

        var graceDates: [Date] = []
        while let log = byDay[checkDay] {
            if log.status == .completed {
                // no grace
            } else if canUseGrace(on: checkDay, graceDates: &graceDates, calendar: calendar) {
                graceDays.insert(checkDay)
            } else {
                break
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDay) else { break }
            checkDay = calendar.startOfDay(for: prev)
        }
        return graceDays
    }

    private static func graceUsedInRollingWindow(
        logs: [HabitLog],
        asOf now: Date,
        calendar: Calendar
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -6, to: today) else { return 0 }
        return graceDaysUsed(logs: logs, templateId: UUID(), asOf: now, calendar: calendar)
            .filter { $0 >= windowStart && $0 <= today }.count
    }
}