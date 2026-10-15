import AppKit
import Observation

/// Shared drag state: which task is in flight and where it would land. A cancelled drag
/// sends no drop callback, so while a drag is active a light poll clears the state once the
/// mouse button has been up for a moment (after any `performDrop` has run).
@MainActor
@Observable
final class TaskDragCoordinator {
    private(set) var draggingID: UUID?
    private(set) var activeZone: String?
    private(set) var insertionIndex: Int?

    @ObservationIgnored private var watchdog: Timer?
    @ObservationIgnored private var releasedTicks = 0

    func begin(_ id: UUID) {
        draggingID = id
        releasedTicks = 0
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkReleased() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    func target(zone: String, index: Int) {
        if activeZone != zone { activeZone = zone }
        if insertionIndex != index { insertionIndex = index }
    }

    func leave(zone: String) {
        guard activeZone == zone else { return }
        activeZone = nil
        insertionIndex = nil
    }

    func end() {
        watchdog?.invalidate()
        watchdog = nil
        draggingID = nil
        activeZone = nil
        insertionIndex = nil
    }

    private func checkReleased() {
        guard NSEvent.pressedMouseButtons & 1 == 0 else {
            releasedTicks = 0
            return
        }
        releasedTicks += 1
        if releasedTicks >= 2 { end() }
    }
}
