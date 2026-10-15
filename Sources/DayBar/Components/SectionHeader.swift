import SwiftUI

/// Sentence-case section title with an optional trailing accessory (counts, badges).
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThemeMetrics.spacingM) {
            Text(title)
                .font(ThemeTypography.sectionHeader)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: ThemeMetrics.spacingS)
            trailing()
                .font(ThemeTypography.meta)
                .foregroundStyle(.secondary)
        }
    }
}
