import SwiftUI
import DayBarCore

/// Three ink bars: ▮▮▮ high, ▮▮▯ medium, ▮▯▯ low. `none` renders an empty track only when
/// `showsEmpty` is set (hover affordance); otherwise it takes no visual weight.
struct PriorityGlyph: View {
    let priority: Priority
    var showsEmpty = false

    @Environment(\.colorSchemeContrast) private var contrast

    private let barWidth: CGFloat = 3
    private let barHeight: CGFloat = 10
    private let barSpacing: CGFloat = 2

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(index < priority.level ? ThemeColors.ink : ThemeColors.priorityTrack(contrast))
                    .frame(width: barWidth, height: barHeight)
            }
        }
        .opacity(priority == .none && !showsEmpty ? 0 : 1)
        .accessibilityHidden(true)
    }
}
