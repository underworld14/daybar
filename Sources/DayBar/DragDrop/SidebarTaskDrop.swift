import SwiftUI

/// Makes a sidebar row accept dragged tasks, with a highlight while one hovers.
struct SidebarTaskDrop: ViewModifier {
    let target: SidebarSelection
    let isTargeted: Bool
    let onTargetChange: (Bool) -> Void
    let perform: (UUID) -> Bool

    @Environment(TaskDragCoordinator.self) private var coordinator: TaskDragCoordinator?

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if isTargeted {
                    RoundedRectangle(cornerRadius: ThemeMetrics.rowRadius, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .padding(-4)
                }
            }
            .dropDestination(for: TaskDragPayload.self) { payloads, _ in
                defer { coordinator?.end() }
                guard let payload = payloads.first else { return false }
                return withThemeAnimation(.reorder) { perform(payload.id) }
            } isTargeted: { targeted in
                onTargetChange(targeted)
            }
    }
}
