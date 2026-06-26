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
    /// Last successful Apple Reminders pull.
    public var remindersLastSyncedAt: Date?
    public var didImportLegacyJSON: Bool = false

    public init(
        lastProcessedDay: Date? = nil,
        lastHabitMaterializedDay: Date? = nil,
        remindersLastSyncedAt: Date? = nil,
        didImportLegacyJSON: Bool = false
    ) {
        self.lastProcessedDay = lastProcessedDay
        self.lastHabitMaterializedDay = lastHabitMaterializedDay
        self.remindersLastSyncedAt = remindersLastSyncedAt
        self.didImportLegacyJSON = didImportLegacyJSON
    }
}
