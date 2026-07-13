import XCTest
@testable import DayBarCore

final class FocusAnalyticsTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    }

    private func session(_ offset: Int, completed: Bool = true, minutes: Int = 25) -> FocusSession {
        FocusSession(endedAt: day(offset).addingTimeInterval(10 * 3600), minutes: minutes, completed: completed)
    }

    func testQualifyingDayCountsCompletedOnly() {
        let sessions = [
            session(0, completed: true),
            session(0, completed: false),
            session(-1, completed: false),
        ]
        let info = FocusAnalytics.streakInfo(sessions: sessions, asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 1)
        let cells = FocusAnalytics.weekStrip(sessions: sessions, days: 7, endingAt: now, calendar: cal)
        XCTAssertEqual(cells.last?.completedSessions, 1)
        XCTAssertEqual(cells[cells.count - 2].completedSessions, 0)
    }

    func testConsecutiveCompletedStreak() {
        let sessions = (0...4).map { session(-$0) }
        let info = FocusAnalytics.streakInfo(sessions: sessions, asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 5)
        XCTAssertEqual(info.best, 5)
    }

    func testIncompleteTodayDoesNotBreakStreak() {
        let sessions = [session(-1), session(-2)]
        let info = FocusAnalytics.streakInfo(sessions: sessions, asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 2)
    }

    func testGraceAllowsOneMissPerWeek() {
        let sessions = [
            session(0),
            session(-2),
            session(-3),
        ]
        let info = FocusAnalytics.streakInfo(sessions: sessions, asOf: now, calendar: cal)
        // day -1 is a miss with grace → streak covers 0, -1(grace), -2, -3
        XCTAssertEqual(info.current, 4)
        XCTAssertEqual(info.graceRemaining, 0)
    }

    func testSecondMissBreaksStreak() {
        let sessions = [
            session(0),
            session(-3),
        ]
        let info = FocusAnalytics.streakInfo(sessions: sessions, asOf: now, calendar: cal)
        // Walk: 0 ok, -1 grace, -2 no grace → streak 2
        XCTAssertEqual(info.current, 2)
    }

    func testBestStreakTracksAcrossBreak() {
        let sessions = [
            session(0),
            session(-1),
            session(-5),
            session(-6),
            session(-7),
            session(-8),
        ]
        let info = FocusAnalytics.streakInfo(sessions: sessions, asOf: now, calendar: cal)
        // Early run -8…-5 plus one grace on -4 → best 5; current uses grace on -2 then stops
        XCTAssertEqual(info.best, 5)
        XCTAssertEqual(info.current, 3)
    }

    func testWeekStripFillLevelsCapAtThree() {
        let sessions = [
            session(0),
            session(0),
            session(0),
            session(0),
            session(-1),
            session(-1),
        ]
        let cells = FocusAnalytics.weekStrip(sessions: sessions, days: 7, endingAt: now, calendar: cal)
        XCTAssertEqual(cells.count, 7)
        XCTAssertEqual(cells.last?.completedSessions, 4)
        XCTAssertEqual(cells.last?.fillLevel, 3)
        XCTAssertEqual(cells[cells.count - 2].completedSessions, 2)
        XCTAssertEqual(cells[cells.count - 2].fillLevel, 2)
        XCTAssertEqual(cells.first?.fillLevel, 0)
    }

    func testWeekStripMarksGraceOnMiss() {
        let sessions = [session(0), session(-2)]
        let cells = FocusAnalytics.weekStrip(sessions: sessions, days: 7, endingAt: now, calendar: cal)
        let miss = cells[cells.count - 2] // yesterday
        XCTAssertEqual(miss.completedSessions, 0)
        XCTAssertTrue(miss.usedGrace)
    }

    func testMilestoneDetection() {
        XCTAssertTrue(FocusAnalytics.isMilestone(7))
        XCTAssertTrue(FocusAnalytics.isMilestone(30))
        XCTAssertTrue(FocusAnalytics.isMilestone(100))
        XCTAssertFalse(FocusAnalytics.isMilestone(6))
    }

    func testEntryCombinesStreakAndStrip() {
        let sessions = [session(0), session(-1)]
        let entry = FocusAnalytics.entry(sessions: sessions, asOf: now, calendar: cal)
        XCTAssertEqual(entry.streak.current, 2)
        XCTAssertEqual(entry.weekCells.count, 7)
        XCTAssertEqual(entry.weekCells.last?.completedSessions, 1)
    }

    func testEmptySessionsYieldZero() {
        let info = FocusAnalytics.streakInfo(sessions: [], asOf: now, calendar: cal)
        XCTAssertEqual(info.current, 0)
        XCTAssertEqual(info.best, 0)
        XCTAssertEqual(info.graceRemaining, FocusAnalytics.gracePerWeek)
    }
}
