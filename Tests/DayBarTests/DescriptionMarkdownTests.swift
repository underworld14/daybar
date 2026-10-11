import XCTest
@testable import DayBarCore

final class DescriptionMarkdownTests: XCTestCase {
    func testWrapsBareURL() {
        XCTAssertEqual(
            DescriptionMarkdown.autolinked("see https://example.com/x here"),
            "see <https://example.com/x> here"
        )
    }

    func testLeavesMarkdownLinksAlone() {
        let input = "[label](https://example.com) stays"
        XCTAssertEqual(DescriptionMarkdown.autolinked(input), input)
    }

    func testLeavesAutolinksAlone() {
        let input = "already <https://example.com> done"
        XCTAssertEqual(DescriptionMarkdown.autolinked(input), input)
    }

    func testPlainTextUntouched() {
        XCTAssertEqual(
            DescriptionMarkdown.autolinked("no links # heading * bold"),
            "no links # heading * bold"
        )
    }

    func testMultipleURLs() {
        XCTAssertEqual(
            DescriptionMarkdown.autolinked("a https://a.io b https://b.io"),
            "a <https://a.io> b <https://b.io>"
        )
    }

    func testEmptyStringUntouched() {
        XCTAssertEqual(DescriptionMarkdown.autolinked(""), "")
    }
}
