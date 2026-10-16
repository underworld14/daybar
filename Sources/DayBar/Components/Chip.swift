import SwiftUI

/// Small capsule label for project, date, and count metadata.
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(ThemeTypography.chip)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.map { $0.opacity(0.16) } ?? ThemeColors.chipFill))
        .foregroundStyle(tint ?? .secondary)
    }
}
