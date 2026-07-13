import Foundation

/// One day cell in the Dayscape week strip.
public struct FocusDayCell: Sendable, Identifiable {
    public let date: Date
    /// Count of naturally completed Pomodoro sessions that day.
    public let completedSessions: Int
    /// True when this empty day consumed a grace slot in the strip window.
    public let usedGrace: Bool

    public var id: Date { date }

    /// Visual saturation 0…3 (cap at 3 completed sessions).
    public var fillLevel: Int { min(3, max(0, completedSessions)) }

    public init(date: Date, completedSessions: Int, usedGrace: Bool = false) {
        self.date = date
        self.completedSessions = completedSessions
        self.usedGrace = usedGrace
    }
}

/// Cached focus streak + 7-day Dayscape strip for the Today panel and Analytics.
public struct FocusStreakEntry: Sendable {
    public let streak: StreakInfo
    public let weekCells: [FocusDayCell]

    public init(streak: StreakInfo, weekCells: [FocusDayCell]) {
        self.streak = streak
        self.weekCells = weekCells
    }
}

/// Pure focus-day aggregation: Dayscape strip, streak, and grace (mirrors HabitAnalytics).
public enum FocusAnalytics {
    public static let gracePerWeek = 1
    public static let milestoneDays: [Int] = [7, 30, 100]
    public static let cacheLookbackDays = 365
    public static let defaultWeekDays = 7

    public static func streakInfo(
        sessions: [FocusSession],
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> StreakInfo {
        let counts = completedCounts(sessions: sessions, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let current = currentStreak(counts: counts, asOf: now, calendar: calendar)
        let best = bestStreak(counts: counts, through: today, calendar: calendar)
        let windowStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let graceUsed = graceDaysChronological(
            counts: counts,
            from: windowStart,
            through: today,
            today: today,
            calendar: calendar
        ).count
        let graceRemaining = max(0, gracePerWeek - graceUsed)
        return StreakInfo(current: current, best: best, graceRemaining: graceRemaining)
    }

    public static func weekStrip(
        sessions: [FocusSession],
        days: Int = defaultWeekDays,
        endingAt now: Date = .now,
        calendar: Calendar = .current
    ) -> [FocusDayCell] {
        let today = calendar.startOfDay(for: now)
        let counts = completedCounts(sessions: sessions, calendar: calendar)
        guard let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return []
        }
        let graceDays = graceDaysChronological(
            counts: counts,
            from: windowStart,
            through: today,
            today: today,
            calendar: calendar
        )

        var cells: [FocusDayCell] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let normalized = calendar.startOfDay(for: day)
            let completed = counts[normalized] ?? 0
            cells.append(FocusDayCell(
                date: normalized,
                completedSessions: completed,
                usedGrace: graceDays.contains(normalized)
            ))
        }
        return cells
    }

    public static func entry(
        sessions: [FocusSession],
        asOf now: Date = .now,
        weekDays: Int = defaultWeekDays,
        calendar: Calendar = .current
    ) -> FocusStreakEntry {
        FocusStreakEntry(
            streak: streakInfo(sessions: sessions, asOf: now, calendar: calendar),
            weekCells: weekStrip(sessions: sessions, days: weekDays, endingAt: now, calendar: calendar)
        )
    }

    public static func isMilestone(_ streak: Int) -> Bool {
        milestoneDays.contains(streak)
    }

    // MARK: - Counts

    private static func completedCounts(
        sessions: [FocusSession],
        calendar: Calendar
    ) -> [Date: Int] {
        var map: [Date: Int] = [:]
        for session in sessions where session.completed {
            let day = calendar.startOfDay(for: session.endedAt)
            map[day, default: 0] += 1
        }
        return map
    }

    // MARK: - Grace

    /// Past empty days between the first focus day and today consume grace.
    /// Days before any completed session do not (no activity yet).
    private static func graceDaysChronological(
        counts: [Date: Int],
        from windowStart: Date,
        through windowEnd: Date,
        today: Date,
        calendar: Calendar
    ) -> Set<Date> {
        guard let earliest = counts.keys.min() else { return [] }
        let start = max(calendar.startOfDay(for: windowStart), earliest)
        let end = calendar.startOfDay(for: windowEnd)
        guard start <= end else { return [] }

        var graceDates: [Date] = []
        var used = Set<Date>()
        var day = start
        while day <= end {
            let completed = counts[day] ?? 0
            if completed == 0, day < today,
               canUseGrace(on: day, graceDates: &graceDates, calendar: calendar) {
                used.insert(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return used
    }

    /// Rolling 7-day window centered so both forward (best/heatmap) and backward
    /// (current streak) walks see prior grace uses.
    private static func canUseGrace(
        on day: Date,
        graceDates: inout [Date],
        calendar: Calendar
    ) -> Bool {
        let windowStart = calendar.date(byAdding: .day, value: -6, to: day) ?? day
        let windowEnd = calendar.date(byAdding: .day, value: 6, to: day) ?? day
        let usedInWindow = graceDates.filter { $0 >= windowStart && $0 <= windowEnd }.count
        guard usedInWindow < gracePerWeek else { return false }
        graceDates.append(day)
        return true
    }

    // MARK: - Streak

    private static func currentStreak(
        counts: [Date: Int],
        asOf now: Date,
        calendar: Calendar
    ) -> Int {
        guard let earliest = counts.keys.min() else { return 0 }
        let today = calendar.startOfDay(for: now)

        var checkDay = today
        if (counts[today] ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            checkDay = calendar.startOfDay(for: yesterday)
        }

        var streak = 0
        var graceDates: [Date] = []

        while checkDay >= earliest {
            let completed = counts[checkDay] ?? 0
            if completed > 0 {
                streak += 1
            } else if canUseGrace(on: checkDay, graceDates: &graceDates, calendar: calendar) {
                streak += 1
            } else {
                break
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDay) else { break }
            checkDay = calendar.startOfDay(for: prev)
        }
        return streak
    }

    private static func bestStreak(
        counts: [Date: Int],
        through endDay: Date,
        calendar: Calendar
    ) -> Int {
        guard let earliest = counts.keys.min() else { return 0 }
        let today = calendar.startOfDay(for: endDay)

        var best = 0
        var current = 0
        var graceDates: [Date] = []
        var day = earliest

        while day <= today {
            let completed = counts[day] ?? 0
            if completed > 0 {
                current += 1
            } else if day < today, canUseGrace(on: day, graceDates: &graceDates, calendar: calendar) {
                // Past miss with grace — like habit `.skipped`.
                current += 1
            } else {
                // Today still empty (in progress) or no grace left — break like habit `.pending`.
                current = 0
                graceDates = []
            }
            best = max(best, current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return best
    }
}
