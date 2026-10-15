import SwiftUI

/// Row frames inside the nearest `TaskDropZone`, keyed by task id.
struct TaskRowFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Reports this row's frame to the enclosing drop zone.
    func taskRowFrame(_ id: UUID) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TaskRowFrameKey.self,
                    value: [id: geometry.frame(in: .named(TaskDropZone.coordinateSpace))]
                )
            }
        }
    }

    /// Makes this row draggable as a DayBar task, with a lifted preview.
    func taskDraggable(_ id: UUID, title: String, coordinator: TaskDragCoordinator?) -> some View {
        draggable(Self.makePayload(id: id, title: title, coordinator: coordinator)) {
            TaskDragPreview(title: title)
        }
    }

    /// Evaluated lazily when the drag actually starts — that's the drag-began signal.
    private static func makePayload(id: UUID, title: String, coordinator: TaskDragCoordinator?) -> TaskDragPayload {
        MainActor.assumeIsolated { coordinator?.begin(id) }
        return TaskDragPayload(id: id, title: title)
    }
}
