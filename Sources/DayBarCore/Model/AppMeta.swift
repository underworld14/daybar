import Foundation

/// Single-row metadata used for idempotent day-rollover. Reference type so the
/// `lastProcessedDay` marker can be mutated in place and persisted in the same save as
/// the carry-over mutations it guards (no divergence between two stores).
public final class AppMeta: Codable {
    public var lastProcessedDay: Date?

    public init(lastProcessedDay: Date? = nil) {
        self.lastProcessedDay = lastProcessedDay
    }
}
