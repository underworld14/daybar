import XCTest
@testable import DayBarCore

final class MoodKeywordHeuristicTests: XCTestCase {
    func testIndonesianHappy() {
        XCTAssertEqual(MoodKeywordHeuristic.classify("aku sangat senang sekali"), .happy)
    }

    func testIndonesianSad() {
        XCTAssertEqual(MoodKeywordHeuristic.classify("aku sangat sedih sekali"), .disappointed)
    }

    func testIndonesianStressed() {
        XCTAssertEqual(
            MoodKeywordHeuristic.classify("pekerjaanku menumpuk dan aku stress sekali"),
            .stressed
        )
    }

    func testEnglishTired() {
        XCTAssertEqual(MoodKeywordHeuristic.classify("I am so tired today"), .tired)
    }

    func testNoMatch() {
        XCTAssertNil(MoodKeywordHeuristic.classify("hari ini biasa saja di kantor"))
    }
}
