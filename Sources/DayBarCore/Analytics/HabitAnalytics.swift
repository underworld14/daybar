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

/// Cached per-template streak + heatmap for analytics and the today panel.
public struct HabitStreakEntry: Identifiable {
    public let template: HabitTemplate
    public let streak: StreakInfo
    public let heatmap: [HabitHeatmapCell]

    public var id: UUID { template.id }

    public init(template: HabitTemplate, streak: StreakInfo, heatmap: [HabitHeatmapCell]) {
        self.template = template
        self.streak = streak
        self.heatmap = heatmap
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
    /// Lookback window for cache rebuilds (heatmap, current streak, grace, best).
    public static let cacheLookbackDays = 365

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
        template: HabitTemplate,
        days: Int,
        endingAt now: Date = .now,
        calendar: Calendar = .current
    ) -> [HabitHeatmapCell] {
        let today = calendar.startOfDay(for: now)
        let templateLogs = logs.filter { $0.templateId == template.id }
        var byDay: [Date: HabitLog] = [:]
        for log in templateLogs {
            byDay[calendar.startOfDay(for: log.day)] = log
        }

        guard let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return []
        }
        let graceDays = graceDaysChronological(
            logs: templateLogs,
            template: template,
            from: windowStart,
            through: today,
            today: today,
            calendar: calendar
        )

        var cells: [HabitHeatmapCell] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let normalized = calendar.startOfDay(for: day)
            guard HabitSchedule.isScheduled(template, on: normalized, calendar: calendar) else {
                cells.append(HabitHeatmapCell(date: normalized, status: nil, usedGrace: false))
                continue
            }
            let log = byDay[normalized]
            let status = log?.status
            let usedGrace = graceDays.contains(normalized)
            cells.append(HabitHeatmapCell(date: normalized, status: status, usedGrace: usedGrace))
        }
        return cells
    }

    public static func streakInfo(
        logs: [HabitLog],
        template: HabitTemplate,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> StreakInfo {
        let templateLogs = logs.filter { $0.templateId == template.id }
        let current = currentStreak(logs: templateLogs, template: template, asOf: now, calendar: calendar)
        let best = bestStreak(logs: templateLogs, template: template, calendar: calendar)
        let graceUsed = graceDaysChronological(
            logs: templateLogs,
            template: template,
            from: calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now,
            through: calendar.startOfDay(for: now),
            today: calendar.startOfDay(for: now),
            calendar: calendar
        ).count
        let graceRemaining = max(0, gracePerWeek - graceUsed)
        return StreakInfo(current: current, best: best, graceRemaining: graceRemaining)
    }

    public static func isMilestone(_ streak: Int) -> Bool {
        milestoneDays.contains(streak)
    }

    // MARK: - Grace helpers

    /// Explicit skip or a past-day still pending — counts toward the weekly grace budget.
    private static func consumesGraceSlot(
        _ status: HabitDayStatus,
        day: Date,
        today: Date
    ) -> Bool {
        switch status {
        case .completed: return false
        case .skipped: return true
        case .pending: return day < today
        }
    }

    /// Walk a date range oldest-first and return scheduled days that consumed a grace slot.
    private static func graceDaysChronological(
        logs: [HabitLog],
        template: HabitTemplate,
        from windowStart: Date,
        through windowEnd: Date,
        today: Date,
        calendar: Calendar
    ) -> Set<Date> {
        let start = calendar.startOfDay(for: windowStart)
        let end = calendar.startOfDay(for: windowEnd)
        var byDay: [Date: HabitLog] = [:]
        for log in logs {
            let day = calendar.startOfDay(for: log.day)
            if day >= start && day <= end { byDay[day] = log }
        }

        var graceDates: [Date] = []
        var used = Set<Date>()
        var day = start
        while day <= end {
            if HabitSchedule.isScheduled(template, on: day, calendar: calendar),
               let log = byDay[day],
               consumesGraceSlot(log.status, day: day, today: today),
               canUseGrace(on: day, graceDates: &graceDates, calendar: calendar) {
                used.insert(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return used
    }

    // MARK: - Streak helpers

    private static func currentStreak(
        logs: [HabitLog],
        template: HabitTemplate,
        asOf now: Date,
        calendar: Calendar
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        let createdDay = calendar.startOfDay(for: template.createdDate)
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
            // Stop once we walk before the habit existed; otherwise every earlier day is
            // "unscheduled" and the loop would decrement through the calendar without bound.
            if checkDay < createdDay { break }
            if !HabitSchedule.isScheduled(template, on: checkDay, calendar: calendar) {
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDay) else { break }
                checkDay = calendar.startOfDay(for: prev)
                continue
            }
            guard let log = byDay[checkDay] else { break }
            switch log.status {
            case .completed:
                streak += 1
            case .skipped:
                if canUseGrace(on: checkDay, graceDates: &graceDates, calendar: calendar) {
                    streak += 1
                } else {
                    return streak
                }
            case .pending:
                return streak
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDay) else { break }
            checkDay = calendar.startOfDay(for: prev)
        }
        return streak
    }

    private static func bestStreak(
        logs: [HabitLog],
        template: HabitTemplate,
        calendar: Calendar
    ) -> Int {
        let sorted = logs.sorted { $0.day < $1.day }
        guard !sorted.isEmpty else { return 0 }

        var byDay: [Date: HabitLog] = [:]
        for log in logs { byDay[calendar.startOfDay(for: log.day)] = log }

        var best = 0
        var current = 0
        var graceDates: [Date] = []
        var previousDay: Date?

        for log in sorted {
            let day = calendar.startOfDay(for: log.day)
            if let prev = previousDay,
               !gapPreservesStreak(from: prev, to: day, template: template, byDay: byDay, calendar: calendar) {
                current = 0
                graceDates = []
            }
            previousDay = day

            guard HabitSchedule.isScheduled(template, on: day, calendar: calendar) else { continue }

            switch log.status {
            case .completed:
                current += 1
            case .skipped:
                if canUseGrace(on: day, graceDates: &graceDates, calendar: calendar) {
                    current += 1
                } else {
                    current = 0
                    graceDates = []
                }
            case .pending:
                current = 0
                graceDates = []
            }
            best = max(best, current)
        }
        return best
    }

    /// True when every scheduled day strictly between `from` and `to` has a completed log.
    private static func gapPreservesStreak(
        from: Date,
        to: Date,
        template: HabitTemplate,
        byDay: [Date: HabitLog],
        calendar: Calendar
    ) -> Bool {
        var day = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        guard day < end else { return true }
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return true }
        day = calendar.startOfDay(for: next)
        while day < end {
            if HabitSchedule.isScheduled(template, on: day, calendar: calendar) {
                guard let log = byDay[day], log.status == .completed else { return false }
            }
            guard let advanced = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: advanced)
        }
        return true
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
}