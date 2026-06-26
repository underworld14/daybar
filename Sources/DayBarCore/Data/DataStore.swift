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
        let schema = Schema([DailyTodo.self, AppMeta.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("DayBar: failed to create ModelContainer: \(error)")
        }
        if !inMemory { importLegacyJSONIfNeeded() }
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

    // MARK: - JSON export / import

    public func exportSnapshot() -> StoreSnapshotDTO {
        let todos = (try? allTodos()) ?? []
        let last = (try? appMeta())?.lastProcessedDay
        return StoreSnapshotDTO(todos: todos.map(TodoDTO.init), meta: MetaDTO(lastProcessedDay: last))
    }

    /// Replace all todos with the snapshot's contents (used by Settings "Import").
    public func importSnapshot(_ snapshot: StoreSnapshotDTO) {
        for existing in (try? allTodos()) ?? [] { context.delete(existing) }
        for dto in snapshot.todos { context.insert(dto.makeModel()) }
        if let last = snapshot.meta?.lastProcessedDay, let meta = try? appMeta() {
            meta.lastProcessedDay = last
        }
        save()
    }

    /// One-time migration of the Phase-1 JSON store into SwiftData (guarded by AppMeta).
    private func importLegacyJSONIfNeeded() {
        guard let meta = try? appMeta(), !meta.didImportLegacyJSON else { return }
        meta.didImportLegacyJSON = true
        let count = (try? context.fetchCount(FetchDescriptor<DailyTodo>())) ?? 0
        if count == 0, let snapshot = JSONStore.loadLegacy() {
            for dto in snapshot.todos { context.insert(dto.makeModel()) }
            if let last = snapshot.meta?.lastProcessedDay { meta.lastProcessedDay = last }
        }
        save()
    }
}
