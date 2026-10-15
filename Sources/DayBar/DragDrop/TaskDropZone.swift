import SwiftUI
import UniformTypeIdentifiers
import DayBarCore

/// Turns a stack of task rows into a drop target with a live insertion line. Rows report
/// their frames with `taskRowFrame(_:)`; drops are clamped to the first
/// `reorderableCount` rows (completed rows stay below).
struct TaskDropZone: ViewModifier {
    static let coordinateSpace = "TaskDropZone"

    let zoneID: String
    /// Row ids in display order.
    let orderedIDs: [UUID]
    let reorderableCount: Int
    /// Whether a drop of this task is welcome here.
    var accepts: (UUID) -> Bool = { _ in true }
    /// Perform the move; return whether it was accepted.
    let onDrop: (_ id: UUID, _ index: Int) -> Bool

    @Environment(TaskDragCoordinator.self) private var coordinator: TaskDragCoordinator?
    @State private var rowFrames: [UUID: CGRect] = [:]

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: Self.coordinateSpace)
            .onPreferenceChange(TaskRowFrameKey.self) { rowFrames = $0 }
            .overlay(alignment: .topLeading) { indicator }
            .onDrop(of: [.dayBarTask], delegate: Delegate(zone: self, coordinator: coordinator))
    }

    @ViewBuilder
    private var indicator: some View {
        // No line where there is no manual order (Done): the column highlight is enough.
        if reorderableCount > 0,
           let coordinator, coordinator.activeZone == zoneID, let index = coordinator.insertionIndex,
           let y = DropInsertionMath.indicatorY(for: index, rowFrames: orderedFrames) {
            InsertionIndicator()
                .offset(y: y - 3.5)
                .transition(.opacity)
        }
    }

    /// One entry per row in display order; `nil` where a row hasn't reported a frame, so
    /// indices stay aligned with `orderedIDs`.
    fileprivate var orderedFrames: [DropInsertionMath.RowFrame?] {
        orderedIDs.map { id in rowFrames[id].map { (Double($0.minY), Double($0.maxY)) } }
    }

    fileprivate func index(at y: CGFloat) -> Int {
        let frames = Array(orderedFrames.prefix(reorderableCount))
        let raw = DropInsertionMath.insertionIndex(locationY: Double(y), rowFrames: frames)
        return DropInsertionMath.clamp(raw, toSegmentCount: reorderableCount)
    }

    private struct Delegate: DropDelegate {
        let zone: TaskDropZone
        let coordinator: TaskDragCoordinator?

        func validateDrop(info: DropInfo) -> Bool {
            guard info.hasItemsConforming(to: [.dayBarTask]) else { return false }
            if let id = coordinator?.draggingID { return zone.accepts(id) }
            return true
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            if let id = coordinator?.draggingID, !zone.accepts(id) {
                coordinator?.leave(zone: zone.zoneID)
                return DropProposal(operation: .forbidden)
            }
            coordinator?.target(zone: zone.zoneID, index: zone.index(at: info.location.y))
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) {
            coordinator?.leave(zone: zone.zoneID)
        }

        func performDrop(info: DropInfo) -> Bool {
            let index = zone.index(at: info.location.y)
            defer { coordinator?.end() }
            if let id = coordinator?.draggingID {
                guard zone.accepts(id) else { return false }
                return withThemeAnimation(.reorder) { zone.onDrop(id, index) }
            }
            // Fallback (no in-app drag state): decode the payload.
            guard let provider = info.itemProviders(for: [.dayBarTask]).first else { return false }
            _ = provider.loadTransferable(type: TaskDragPayload.self) { result in
                guard case .success(let payload) = result else { return }
                Task { @MainActor in
                    guard zone.accepts(payload.id) else { return }
                    withThemeAnimation(.reorder) { _ = zone.onDrop(payload.id, index) }
                }
            }
            return true
        }
    }
}

extension View {
    func taskDropZone(
        _ zoneID: String,
        orderedIDs: [UUID],
        reorderableCount: Int,
        accepts: @escaping (UUID) -> Bool = { _ in true },
        onDrop: @escaping (_ id: UUID, _ index: Int) -> Bool
    ) -> some View {
        modifier(TaskDropZone(
            zoneID: zoneID, orderedIDs: orderedIDs, reorderableCount: reorderableCount,
            accepts: accepts, onDrop: onDrop
        ))
    }
}
