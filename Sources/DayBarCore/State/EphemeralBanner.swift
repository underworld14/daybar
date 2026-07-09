import Foundation

/// A short, dismissible, non-modal panel message (milestones, quiet acknowledgments, undo).
public struct EphemeralBanner: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var message: String
    public var undoLabel: String?
    /// Opaque token the UI passes back to `AppState.performUndo(token:)`.
    public var undoToken: String?

    public init(
        id: UUID = UUID(),
        message: String,
        undoLabel: String? = nil,
        undoToken: String? = nil
    ) {
        self.id = id
        self.message = message
        self.undoLabel = undoLabel
        self.undoToken = undoToken
    }
}
