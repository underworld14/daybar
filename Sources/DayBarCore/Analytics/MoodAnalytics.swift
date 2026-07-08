import Foundation

/// One aggregated period for the mood chart. No re-inference happens here — scores are
/// read straight off each `DayLog.moodScore`, which was looked up from `MoodTag.score`
/// at save time (see `DayLog`/`MoodTag`).
public struct MoodStatBucket: Sendable, Identifiable {
    public let date: Date
    public var averageScore: Double?   // nil if no logged mood in the period
    public var loggedDays: Int

    public var id: Date { date }

    public init(date: Date, averageScore: Double? = nil, loggedDays: Int = 0) {
        self.date = date
        self.averageScore = averageScore
        self.loggedDays = loggedDays
    }
}

/// Pure, testable aggregation over `DayLog`s — mirrors `Analytics`/`HabitAnalytics`.
public enum MoodAnalytics {
    public static func buckets(
        dayLogs: [DayLog],
        endingAt now: Date = .now,
        count: Int,
        granularity: Granularity,
        calendar: Calendar = .current
    ) -> [MoodStatBucket] {
        let last = Analytics.periodStart(now, granularity, calendar: calendar)
        var starts: [Date] = []
        for i in stride(from: count - 1, through: 0, by: -1) {
            starts.append(Analytics.advance(last, granularity, by: -i, calendar: calendar))
        }
        var map: [Date: MoodStatBucket] = [:]
        for s in starts { map[s] = MoodStatBucket(date: s) }

        func key(for date: Date) -> Date? {
            let s = Analytics.periodStart(date, granularity, calendar: calendar)
            return map[s] != nil ? s : nil
        }

        var scoreSums: [Date: Int] = [:]
        for log in dayLogs {
            guard let score = log.moodScore, let s = key(for: log.day) else { continue }
            scoreSums[s, default: 0] += score
            map[s]?.loggedDays += 1
        }
        for s in starts {
            guard let sum = scoreSums[s], let bucket = map[s], bucket.loggedDays > 0 else { continue }
            map[s]?.averageScore = Double(sum) / Double(bucket.loggedDays)
        }
        return starts.compactMap { map[$0] }
    }

    /// Overall average across buckets, weighted by `loggedDays` per bucket. A plain mean of
    /// bucket averages would let a sparsely-logged bucket outvote a densely-logged one (and
    /// could even flip the sign) — this reconstructs the true per-day mean instead.
    public static func overallAverageScore(_ buckets: [MoodStatBucket]) -> Double? {
        let totalDays = buckets.reduce(0) { $0 + $1.loggedDays }
        guard totalDays > 0 else { return nil }
        let scoreSum = buckets.reduce(0.0) { $0 + ($1.averageScore ?? 0) * Double($1.loggedDays) }
        return scoreSum / Double(totalDays)
    }
}
