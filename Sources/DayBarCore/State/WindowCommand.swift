import Foundation

/// Main-menu commands for the main window's board. The menu (declared on the SwiftUI app)
/// can't see the AppKit-hosted window's selection, so it posts a request that the board
/// view applies to its selected task.
public enum WindowCommand: Equatable, Sendable {
    case toggleInspector
    case completeSelected
    case toggleStartSelected
    case setPriority(Priority)
    case moveSelectedToToday
    case moveSelectedToTomorrow
    case dropSelected
}

public struct WindowCommandRequest: Equatable, Sendable {
    public let id: UUID
    public let command: WindowCommand

    public init(id: UUID = UUID(), command: WindowCommand) {
        self.id = id
        self.command = command
    }
}
