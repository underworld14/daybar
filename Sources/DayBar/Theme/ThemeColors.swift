import SwiftUI

/// Native+ color slots. Everything maps to system semantic colors (so the system accent,
/// light/dark, and Increase Contrast keep working); the one brand note is the indigo ink
/// used for priority bars and the Dayscape strip.
enum ThemeColors {
    /// Brand ink shared by the priority glyph and the Dayscape strip.
    static let ink = Color.indigo

    static let rowHover = Color.primary.opacity(0.05)
    static let rowSelected = Color.accentColor.opacity(0.16)
    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let cardHover = Color.primary.opacity(0.04)
    static let columnFill = Color.primary.opacity(0.035)
    static let chipFill = Color.primary.opacity(0.06)
    static let fieldFill = Color.primary.opacity(0.04)
    static let fieldFillFocused = Color.primary.opacity(0.07)

    static let statusTodo = Color.secondary
    static let statusProgress = Color.accentColor
    static let statusDone = Color.green
    static let aging = Color.orange

    static let dropTarget = Color.accentColor.opacity(0.08)
    static let insertionLine = Color.accentColor

    /// Hairline used for card and field borders; stronger under Increase Contrast.
    static func hairline(_ contrast: ColorSchemeContrast) -> Color {
        Color.primary.opacity(contrast == .increased ? 0.35 : 0.09)
    }

    /// Unfilled priority bar; stronger under Increase Contrast so the count stays legible.
    static func priorityTrack(_ contrast: ColorSchemeContrast) -> Color {
        Color.primary.opacity(contrast == .increased ? 0.35 : 0.14)
    }
}
