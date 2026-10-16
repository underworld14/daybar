import SwiftUI

/// Semantic type roles (system font, Dynamic Type friendly).
enum ThemeTypography {
    static let wordmark = Font.system(.title3, design: .rounded).weight(.bold)
    static let boardTitle = Font.system(.title3, design: .rounded).weight(.semibold)
    /// Sentence-case section headers ("Today", "Carried over") instead of tracked caps.
    static let sectionHeader = Font.subheadline.weight(.semibold)
    static let rowTitle = Font.body
    static let cardTitle = Font.callout
    static let meta = Font.caption.monospacedDigit()
    static let chip = Font.caption2
}
