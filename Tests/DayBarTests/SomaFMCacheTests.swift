import XCTest
@testable import DayBarCore

final class SomaFMCacheTests: XCTestCase {
    func testCacheFreshnessWithinTTL() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fetchedAt = now.addingTimeInterval(-1800)
        XCTAssertTrue(SomaFMService.isCacheFresh(fetchedAt: fetchedAt, now: now, ttl: 3600))
    }

    func testCacheStaleAfterTTL() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fetchedAt = now.addingTimeInterval(-7200)
        XCTAssertFalse(SomaFMService.isCacheFresh(fetchedAt: fetchedAt, now: now, ttl: 3600))
    }
}
