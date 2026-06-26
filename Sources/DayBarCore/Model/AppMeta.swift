import Foundation
import SwiftData

/// Single-row metadata, persisted with SwiftData so the rollover marker is written in the
/// same transaction as the carry-over mutations it guards. `didImportLegacyJSON` guards the
/// one-time import from the Phase 1 JSON store.
@Model
public final class AppMeta {
    public var lastProcessedDay: Date?
    /// Last calendar day for which `HabitEngine` materialized logs (idempotency key).
    public var lastHabitMaterializedDay: Date?
    public var didImportLegacyJSON: Bool = false

    public init(
        lastProcessedDay: Date? = nil,
        lastHabitMaterializedDay: Date? = nil,
        didImportLegacyJSON: Bool = false
    ) {
        self.lastProcessedDay = lastProcessedDay
        self.lastHabitMaterializedDay = lastHabitMaterializedDay
        self.didImportLegacyJSON = didImportLegacyJSON
    }
}
