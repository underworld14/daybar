import XCTest
@testable import DayBarCore

final class QuickAddParserTests: XCTestCase {
    private let client = QuickAddParser.ProjectRef(id: UUID(), name: "Client work")
    private let clinic = QuickAddParser.ProjectRef(id: UUID(), name: "Clinic")
    private let home = QuickAddParser.ProjectRef(id: UUID(), name: "Home")
    private var projects: [QuickAddParser.ProjectRef] { [client, clinic, home] }

    func testPlainTitle() {
        let result = QuickAddParser.parse("  Buy   coffee beans ")
        XCTAssertEqual(result?.title, "Buy coffee beans")
        XCTAssertNil(result?.priority)
        XCTAssertNil(result?.day)
        XCTAssertEqual(result?.tokens, [])
    }

    func testPriorityMarks() {
        XCTAssertEqual(QuickAddParser.parse("A !")?.priority, .low)
        XCTAssertEqual(QuickAddParser.parse("A !!")?.priority, .medium)
        XCTAssertEqual(QuickAddParser.parse("!!! A")?.priority, .high)
        XCTAssertEqual(QuickAddParser.parse("A !!")?.title, "A")
    }

    func testExclamationInsideAWordIsTitle() {
        let result = QuickAddParser.parse("Hello! world")
        XCTAssertEqual(result?.title, "Hello! world")
        XCTAssertNil(result?.priority)
    }

    func testDayWordsInEnglishAndIndonesian() {
        XCTAssertEqual(QuickAddParser.parse("Call mom tomorrow")?.day, .tomorrow)
        XCTAssertEqual(QuickAddParser.parse("Call mom tmr")?.day, .tomorrow)
        XCTAssertEqual(QuickAddParser.parse("Call mom BESOK")?.day, .tomorrow)
        XCTAssertEqual(QuickAddParser.parse("besok call mom")?.title, "call mom")
        XCTAssertEqual(QuickAddParser.parse("Call mom today")?.day, .today)
        let hariIni = QuickAddParser.parse("Bayar listrik hari ini ya")
        XCTAssertEqual(hariIni?.day, .today)
        XCTAssertEqual(hariIni?.title, "Bayar listrik ya")
    }

    func testHariAloneIsTitle() {
        let result = QuickAddParser.parse("Hari raya prep")
        XCTAssertNil(result?.day)
        XCTAssertEqual(result?.title, "Hari raya prep")
    }

    func testProjectExactThenUniquePrefix() {
        XCTAssertEqual(QuickAddParser.parse("Invoice #clientwork", projects: projects)?.projectID, client.id)
        XCTAssertEqual(QuickAddParser.parse("Invoice #Client-Work", projects: projects)?.projectID, client.id)
        XCTAssertEqual(QuickAddParser.parse("Invoice #clie", projects: projects)?.projectID, client.id)
        XCTAssertEqual(QuickAddParser.parse("Clean #home", projects: projects)?.projectID, home.id)
    }

    func testAmbiguousOrUnknownTagStaysInTitle() {
        let ambiguous = QuickAddParser.parse("Book #cli", projects: projects)
        XCTAssertNil(ambiguous?.projectID)
        XCTAssertEqual(ambiguous?.title, "Book #cli")
        let unknown = QuickAddParser.parse("Fix bug #123", projects: projects)
        XCTAssertNil(unknown?.projectID)
        XCTAssertEqual(unknown?.title, "Fix bug #123")
    }

    func testCombinedSyntax() {
        let result = QuickAddParser.parse("Send invoice !!! #client besok", projects: projects)
        XCTAssertEqual(result?.title, "Send invoice")
        XCTAssertEqual(result?.priority, .high)
        XCTAssertEqual(result?.day, .tomorrow)
        XCTAssertEqual(result?.projectID, client.id)
        XCTAssertEqual(result?.tokens.count, 3)
    }

    func testLastTokenOfAKindWins() {
        let result = QuickAddParser.parse("Plan ! !!! today besok")
        XCTAssertEqual(result?.priority, .high)
        XCTAssertEqual(result?.day, .tomorrow)
    }

    func testBackslashEscapesAToken() {
        let result = QuickAddParser.parse("Read \\besok novel \\!!!")
        XCTAssertEqual(result?.title, "Read besok novel !!!")
        XCTAssertNil(result?.day)
        XCTAssertNil(result?.priority)
    }

    func testOnlySyntaxIsNil() {
        XCTAssertNil(QuickAddParser.parse("!!! besok"))
        XCTAssertNil(QuickAddParser.parse("   "))
    }
}
