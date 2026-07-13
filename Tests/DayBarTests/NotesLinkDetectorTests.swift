import XCTest
@testable import DayBarCore

final class NotesLinkDetectorTests: XCTestCase {
    func testDetectsHTTPSURL() {
        let urls = NotesLinkDetector.urls(
            in: "See https://mysales.atlassian.net/browse/QRD-1000 for context"
        )
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://mysales.atlassian.net/browse/QRD-1000"
        ])
    }

    func testDetectsMultipleUniqueURLs() {
        let text = """
        First: https://example.com/a
        Second: https://example.com/b
        Dup: https://example.com/a
        """
        let urls = NotesLinkDetector.urls(in: text)
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://example.com/a",
            "https://example.com/b",
        ])
    }

    func testEmptyAndPlainText() {
        XCTAssertTrue(NotesLinkDetector.urls(in: "").isEmpty)
        XCTAssertTrue(NotesLinkDetector.urls(in: "no links here").isEmpty)
    }
}
