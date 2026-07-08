import XCTest
@testable import DayBarCore

final class MoodAnalyticsTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    }

    func testBucketAveragesScoresWithinPeriod() {
        let logs = [
            DayLog(day: day(0), moodTag: .happy, moodSource: .manual),   // +1
            DayLog(day: day(-1), moodTag: .stressed, moodSource: .ai),   // -2
        ]
        let buckets = MoodAnalytics.buckets(dayLogs: logs, endingAt: now, count: 7, granularity: .day, calendar: cal)
        XCTAssertEqual(buckets.count, 7)
        XCTAssertEqual(buckets.last?.averageScore, 1)
        XCTAssertEqual(buckets.last?.loggedDays, 1)
        let prior = buckets[buckets.count - 2]
        XCTAssertEqual(prior.averageScore, -2)
    }

    func testDaysWithoutMoodAreNilNotZero() {
        let logs = [DayLog(day: day(0), reflection: "no mood set today")]
        let buckets = MoodAnalytics.buckets(dayLogs: logs, endingAt: now, count: 3, granularity: .day, calendar: cal)
        XCTAssertNil(buckets.last?.averageScore, "a day with a reflection but no mood must not average to 0")
        XCTAssertEqual(buckets.last?.loggedDays, 0)
    }

    func testOverallAverageIsWeightedByLoggedDaysNotBucketCount() throws {
        // One sparsely-logged bucket (+2 over 1 day) vs. one densely-logged bucket
        // (-1 over 5 days). An unweighted mean-of-means would report +0.5 (wrong sign);
        // the correct day-weighted mean is ((1*2) + (5*-1)) / 6.
        let buckets = [
            MoodStatBucket(date: Date(timeIntervalSince1970: 0), averageScore: 2, loggedDays: 1),
            MoodStatBucket(date: Date(timeIntervalSince1970: 86_400), averageScore: -1, loggedDays: 5),
        ]
        let overall = try XCTUnwrap(MoodAnalytics.overallAverageScore(buckets))
        XCTAssertEqual(overall, -0.5, accuracy: 0.0001)
    }

    func testOverallAverageIsNilWhenNoDaysLogged() {
        let buckets = [MoodStatBucket(date: Date(timeIntervalSince1970: 0), averageScore: nil, loggedDays: 0)]
        XCTAssertNil(MoodAnalytics.overallAverageScore(buckets))
    }

    func testMultipleLogsInSamePeriodAverageTogether() {
        // Two "days" landing in the same week bucket.
        let logs = [
            DayLog(day: day(0), moodTag: .proud, moodSource: .manual),      // +2
            DayLog(day: day(-1), moodTag: .disappointed, moodSource: .ai),  // -2
        ]
        let buckets = MoodAnalytics.buckets(dayLogs: logs, endingAt: now, count: 1, granularity: .week, calendar: cal)
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets.first?.averageScore, 0)
        XCTAssertEqual(buckets.first?.loggedDays, 2)
    }
}
