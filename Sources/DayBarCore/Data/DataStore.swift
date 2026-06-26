import Foundation
import SwiftData

/// SwiftData-backed persistence with typed query helpers. The public surface is identical to
/// the Phase-1 JSON store, so `RolloverEngine`/`AppState` are unchanged. Day-boundary dates
/// are computed by the caller and injected into `#Predicate`s (never `Calendar` calls or
/// view `@State` inside a predicate).
@MainActor
public final class DataStore {
    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }

    public init(inMemory: Bool = false) {
        let schema = Schema([DailyTodo.self, AppMeta.self, FocusSession.self, DayLog.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("DayBar: failed to create ModelContainer: \(error)")
        }
        if !inMemory {
            performLegacyImport(
                snapshot: JSONStore.loadLegacy(),
                legacyFileExists: FileManager.default.fileExists(atPath: JSONStore.legacyFileURL.path)
            )
        }
    }

    /// Explicit save — SwiftData autosave can fail silently, so mutations call this.
    public func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("DayBar: save error: \(error)")
        }
    }

    @discardableResult
    public func insert(_ todo: DailyTodo) -> DailyTodo {
        context.insert(todo)
        return todo
    }

    public func delete(_ todo: DailyTodo) {
        context.delete(todo)
    }

    public func allTodos() throws -> [DailyTodo] {
        try context.fetch(FetchDescriptor<DailyTodo>(sortBy: [SortDescriptor(\.createdDate)]))
    }

    // MARK: - Queries

    /// Non-dropped todos planned for the given calendar day, high priority first.
    public func todos(on day: Date, calendar: Calendar = .current) throws -> [DailyTodo] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let dropped = TodoStatus.dropped.rawValue
        let predicate = #Predicate<DailyTodo> { todo in
            todo.plannedForDate >= start && todo.plannedForDate < end && todo.statusRaw != dropped
        }
        return try context.fetch(FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.priorityRaw, order: .reverse), SortDescriptor(\.createdDate)]
        ))
    }

    /// Past-due, not-completed, not-dropped todos before the given day — the carry-over backlog.
    public func overdueIncompleteTodos(before day: Date, calendar: Calendar = .current) throws -> [DailyTodo] {
        let start = calendar.startOfDay(for: day)
        let dropped = TodoStatus.dropped.rawValue
        let predicate = #Predicate<DailyTodo> { todo in
            todo.plannedForDate < start && todo.completedDate == nil && todo.statusRaw != dropped
        }
        return try context.fetch(FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.originalPlannedDate), SortDescriptor(\.createdDate)]
        ))
    }

    /// The single metadata row, creating it on first access.
    public func appMeta() throws -> AppMeta {
        if let existing = try context.fetch(FetchDescriptor<AppMeta>()).first {
            return existing
        }
        let meta = AppMeta()
        context.insert(meta)
        return meta
    }

    // MARK: - Focus sessions & day logs (analytics + review)

    @discardableResult
    public func insert(_ session: FocusSession) -> FocusSession {
        context.insert(session)
        return session
    }

    public func focusSessions(in range: Range<Date>) throws -> [FocusSession] {
        let start = range.lowerBound, end = range.upperBound
        let predicate = #Predicate<FocusSession> { $0.endedAt >= start && $0.endedAt < end }
        return try context.fetch(FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.endedAt)]))
    }

    /// Non-dropped todos whose ORIGINAL planned date falls in the range (for analytics binning).
    public func todos(plannedIn range: Range<Date>) throws -> [DailyTodo] {
        let start = range.lowerBound, end = range.upperBound
        let dropped = TodoStatus.dropped.rawValue
        let predicate = #Predicate<DailyTodo> {
            $0.originalPlannedDate >= start && $0.originalPlannedDate < end && $0.statusRaw != dropped
        }
        return try context.fetch(FetchDescriptor(predicate: predicate))
    }

    public func dayLog(for day: Date, calendar: Calendar = .current) throws -> DayLog? {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = #Predicate<DayLog> { $0.day >= start && $0.day < end }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    public func hasDayLog(on day: Date, calendar: Calendar = .current) -> Bool {
        ((try? dayLog(for: day, calendar: calendar)) ?? nil) != nil
    }

    @discardableResult
    public func upsertDayLog(day: Date, reflection: String, plannedCount: Int, completedCount: Int, calendar: Calendar = .current) -> DayLog {
        let start = calendar.startOfDay(for: day)
        if let existing = (try? dayLog(for: start, calendar: calendar)) ?? nil {
            existing.reflection = reflection
            existing.plannedCount = plannedCount
            existing.completedCount = completedCount
            save()
            return existing
        }
        let log = DayLog(day: start, reflection: reflection, plannedCount: plannedCount, completedCount: completedCount)
        context.insert(log)
        save()
        return log
    }

    // MARK: - JSON export / import

    public func exportSnapshot() -> StoreSnapshotDTO {
        let todos = (try? allTodos()) ?? []
        let last = (try? appMeta())?.lastProcessedDay
        return StoreSnapshotDTO(todos: todos.map(TodoDTO.init), meta: MetaDTO(lastProcessedDay: last))
    }

    /// Replace ALL todos with the snapshot's contents (used by Settings "Import"). Destructive
    /// by design — the caller should confirm with the user first. Deletes are committed before
    /// the re-inserts so preserved ids can't collide with the `@Attribute(.unique)` index.
    public func importSnapshot(_ snapshot: StoreSnapshotDTO) {
        for existing in (try? allTodos()) ?? [] { context.delete(existing) }
        save()
        for dto in snapshot.todos { context.insert(dto.makeModel()) }
        if let last = snapshot.meta?.lastProcessedDay, let meta = try? appMeta() {
            meta.lastProcessedDay = last
        }
        save()
    }

    /// One-time migration of the Phase-1 JSON store into SwiftData. Idempotent (guarded by
    /// `AppMeta.didImportLegacyJSON`). Internal + injectable so it is unit-testable. The guard
    /// is burned only once the migration is genuinely settled: a present-but-unreadable file
    /// leaves it unset so a transient read failure retries next launch instead of silently
    /// discarding the Phase-1 data.
    func performLegacyImport(snapshot: StoreSnapshotDTO?, legacyFileExists: Bool) {
        guard let meta = try? appMeta(), !meta.didImportLegacyJSON else { return }

        // Store already has data → migration is effectively done; never overwrite.
        let count = (try? context.fetchCount(FetchDescriptor<DailyTodo>())) ?? 0
        if count > 0 {
            meta.didImportLegacyJSON = true
            save()
            return
        }

        // No legacy file → nothing to migrate, ever.
        if !legacyFileExists {
            meta.didImportLegacyJSON = true
            save()
            return
        }

        // File present but unreadable/corrupt → leave the guard unset and retry next launch.
        guard let snapshot else { return }

        for dto in snapshot.todos { context.insert(dto.makeModel()) }
        if let last = snapshot.meta?.lastProcessedDay { meta.lastProcessedDay = last }
        meta.didImportLegacyJSON = true
        save()
    }
}
