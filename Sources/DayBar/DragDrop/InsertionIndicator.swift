import SwiftUI

/// Accent line (with a leading dot) showing where a dragged task will land.
struct InsertionIndicator: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .strokeBorder(ThemeColors.insertionLine, lineWidth: 2)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(ThemeColors.insertionLine)
                .frame(height: 2)
        }
        .frame(height: 7)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
