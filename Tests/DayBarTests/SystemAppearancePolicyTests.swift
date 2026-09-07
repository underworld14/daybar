import AppKit
import XCTest
@testable import DayBarCore

final class SystemAppearancePolicyTests: XCTestCase {
    func testResolvesStandardAquaAppearances() throws {
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))

        XCTAssertEqual(SystemAppearancePolicy.resolvedName(for: light), .aqua)
        XCTAssertEqual(SystemAppearancePolicy.resolvedName(for: dark), .darkAqua)
    }

    func testPreservesAccessibilityHighContrastAppearances() throws {
        XCTAssertEqual(
            SystemAppearancePolicy.resolvedName(fromMatch: .accessibilityHighContrastAqua),
            .accessibilityHighContrastAqua
        )
        XCTAssertEqual(
            SystemAppearancePolicy.resolvedName(fromMatch: .accessibilityHighContrastDarkAqua),
            .accessibilityHighContrastDarkAqua
        )
    }
}
