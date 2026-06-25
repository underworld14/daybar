import Foundation

/// Local JSON-file persistence with typed query helpers. Holds the todos and the single
/// `AppMeta` in memory and writes an atomic JSON snapshot on `save()`. The query helpers
/// take an injected day so callers never embed calendar math in storage internals.
///
/// This is the P1 store (Command Line Tools compatible). The public surface — `insert`,
/// `delete`, `save`, `todos(on:)`, `overdueIncompleteTodos(before:)`, `appMeta()` — is the
/// seam a SwiftData-backed implementation will slot into once Xcode is available.
@MainActor
public final class DataStore {
    private var todos: [DailyTodo]
    public let meta: AppMeta
    private let fileURL: URL?

    public init(inMemory: Bool = false) {
        let url = inMemory ? nil : Self.defaultFileURL()
        self.fileURL = url
        if let url, let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder.dayBar.decode(StoreSnapshot.self, from: data) {
            self.todos = snapshot.todos
            self.meta = snapshot.meta
        } else {
            self.todos = []
            self.meta = AppMeta()
        }
    }

    /// Persist the current snapshot. No-op for in-memory stores (tests).
    public func save() {
        guard let url = fileURL else { return }
        let snapshot = StoreSnapshot(todos: todos, meta: meta)
        do {
            let data = try JSONEncoder.dayBar.encode(snapshot)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            print("DayBar: save error: \(error)")
        }
    }

    @discardableResult
    public func insert(_ todo: DailyTodo) -> DailyTodo {
        todos.append(todo)
        return todo
    }

    public func delete(_ todo: DailyTodo) {
        todos.removeAll { $0.id == todo.id }
    }

    public func allTodos() -> [DailyTodo] { todos }

    // MARK: - Queries

    /// Non-dropped todos planned for the given calendar day, high priority first.
    public func todos(on day: Date, calendar: Calendar = .current) throws -> [DailyTodo] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return todos
            .filter { $0.plannedForDate >= start && $0.plannedForDate < end && $0.status != .dropped }
            .sorted(by: Self.byPriorityThenCreated)
    }

    /// Past-due, not-completed, not-dropped todos before the given day — the carry-over
    /// backlog. Oldest first.
    public func overdueIncompleteTodos(before day: Date, calendar: Calendar = .current) throws -> [DailyTodo] {
        let start = calendar.startOfDay(for: day)
        return todos
            .filter { $0.plannedForDate < start && $0.completedDate == nil && $0.status != .dropped }
            .sorted(by: Self.byOriginalThenCreated)
    }

    public func appMeta() throws -> AppMeta { meta }

    // MARK: - Internals

    private static func byPriorityThenCreated(_ lhs: DailyTodo, _ rhs: DailyTodo) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        return lhs.createdDate < rhs.createdDate
    }

    private static func byOriginalThenCreated(_ lhs: DailyTodo, _ rhs: DailyTodo) -> Bool {
        if lhs.originalPlannedDate != rhs.originalPlannedDate { return lhs.originalPlannedDate < rhs.originalPlannedDate }
        return lhs.createdDate < rhs.createdDate
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("DayBar", isDirectory: true)
            .appendingPathComponent("daybar-store.json")
    }
}

/// On-disk snapshot of the whole store.
struct StoreSnapshot: Codable {
    var todos: [DailyTodo]
    var meta: AppMeta
}

private extension JSONEncoder {
    static let dayBar: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

private extension JSONDecoder {
    static let dayBar: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
