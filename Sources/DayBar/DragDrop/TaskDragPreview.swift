import SwiftUI

/// The lifted card that follows the pointer while dragging a task.
struct TaskDragPreview: View {
    let title: String

    var body: some View {
        HStack(spacing: ThemeMetrics.spacingS) {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
            Text(title)
                .lineLimit(1)
        }
        .font(ThemeTypography.rowTitle)
        .padding(.horizontal, ThemeMetrics.spacingL)
        .padding(.vertical, ThemeMetrics.spacingS + 2)
        .frame(maxWidth: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ThemeMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ThemeMetrics.cardRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.5))
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}
