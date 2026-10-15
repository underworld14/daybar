import SwiftUI

/// Vertical stack of `TaskRowView`s, outset so each row's status ring lines up with the
/// section header text while its hover highlight bleeds into the margin.
struct TaskRowStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.leading, -ThemeMetrics.rowLeadingInset)
        .padding(.trailing, -ThemeMetrics.rowHorizontalPadding)
    }
}
