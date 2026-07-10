import XCTest
@testable import DayBarCore

final class UpdateConfigurationTests: XCTestCase {
    func testFeedURLUsesHTTPSAndAppcastPath() {
        XCTAssertEqual(UpdateConfiguration.feedURL.scheme, "https")
        XCTAssertTrue(UpdateConfiguration.feedURL.absoluteString.hasSuffix("/appcast.xml"))
    }

    func testScheduledCheckIntervalIsOneDay() {
        XCTAssertEqual(UpdateConfiguration.scheduledCheckInterval, 86_400)
    }

    func testCompareVersionsOrdersSemverNumerically() {
        XCTAssertEqual(UpdateConfiguration.compareVersions("0.10.0", "0.3.0"), .orderedDescending)
        XCTAssertEqual(UpdateConfiguration.compareVersions("0.3.0", "0.3.0"), .orderedSame)
        XCTAssertEqual(UpdateConfiguration.compareVersions("0.2.9", "0.3.0"), .orderedAscending)
    }

    func testIsNewerVersion() {
        XCTAssertTrue(UpdateConfiguration.isNewerVersion("0.4.0", than: "0.3.0"))
        XCTAssertFalse(UpdateConfiguration.isNewerVersion("0.3.0", than: "0.3.1"))
    }
}
