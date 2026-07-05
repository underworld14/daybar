import XCTest
@testable import DayBarCore

final class PLSParserTests: XCTestCase {
    func testParseStreamURLFromPLS() throws {
        let pls = """
        [playlist]
        NumberOfEntries=1
        File1=http://stream.example.com/live.mp3
        """
        let url = try PLSParser.parseStreamURL(from: pls)
        XCTAssertEqual(url.absoluteString, "http://stream.example.com/live.mp3")
    }

    func testParseMissingFile1Throws() {
        XCTAssertThrowsError(try PLSParser.parseStreamURL(from: "[playlist]\nTitle=Test")) { error in
            XCTAssertEqual(error as? PLSParserError, .streamURLNotFound)
        }
    }
}

extension PLSParserError: Equatable {
    public static func == (lhs: PLSParserError, rhs: PLSParserError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidResponse, .invalidResponse): return true
        case (.streamURLNotFound, .streamURLNotFound): return true
        default: return false
        }
    }
}
