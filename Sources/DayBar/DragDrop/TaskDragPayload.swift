import CoreTransferable
import Foundation

/// What a dragged task carries. Inside DayBar it moves the task; dropped into another app
/// it becomes the task's title as plain text.
struct TaskDragPayload: Codable, Transferable {
    let id: UUID
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .dayBarTask)
        ProxyRepresentation(exporting: \.title)
    }
}
