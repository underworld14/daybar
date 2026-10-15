import CoreGraphics

/// Spacing, radii, and sizes shared by tray and window components (8pt rhythm,
/// compact Mac control sizes).
enum ThemeMetrics {
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 6
    static let spacingM: CGFloat = 8
    static let spacingL: CGFloat = 12
    static let spacingXL: CGFloat = 16

    static let rowRadius: CGFloat = 6
    static let cardRadius: CGFloat = 10
    static let columnRadius: CGFloat = 12
    static let fieldRadius: CGFloat = 8

    static let rowVerticalPadding: CGFloat = 3
    static let rowHorizontalPadding: CGFloat = 6
    static let cardPadding: CGFloat = 10

    /// Visual diameter of the status ring; its hit target is `statusHitSize`.
    static let statusRingSize: CGFloat = 15
    static let statusHitSize: CGFloat = 22

    /// Distance from a row's edge to its status ring's visible edge — rows are outset by
    /// this so rings align with section headers.
    static let rowLeadingInset: CGFloat = rowHorizontalPadding + (statusHitSize - statusRingSize) / 2

    static let hairlineWidth: CGFloat = 1
    static let minColumnWidth: CGFloat = 220
}
