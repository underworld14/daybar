import Foundation

/// Codable transfer objects for JSON export/import and the one-time Phase-1 import.
/// Kept separate from the SwiftData `@Model` types so persistence and serialization stay
/// decoupled. Field names + ISO-8601 dates match the Phase-1 `daybar-store.json` shape.
public struct TodoDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var createdDate: Date
    public var plannedForDate: Date
    public var originalPlannedDate: Date
    public var dueDate: Date?
    public var completedDate: Date?
    public var statusRaw: String
    public var priorityRaw: Int
    public var delayCount: Int
    public var snoozedUntil: Date?
    public var pomodoroCount: Int
    public var sourceRaw: String
    public var externalIdentifier: String?
}

public struct MetaDTO: Codable, Sendable {
    public var lastProcessedDay: Date?
}

public struct StoreSnapshotDTO: Codable, Sendable {
    public var todos: [TodoDTO]
    public var meta: MetaDTO?

    public init(todos: [TodoDTO], meta: MetaDTO? = nil) {
        self.todos = todos
        self.meta = meta
    }
}

public extension TodoDTO {
    init(_ m: DailyTodo) {
        self.init(
            id: m.id, title: m.title, notes: m.notes, createdDate: m.createdDate,
            plannedForDate: m.plannedForDate, originalPlannedDate: m.originalPlannedDate,
            dueDate: m.dueDate, completedDate: m.completedDate, statusRaw: m.statusRaw,
            priorityRaw: m.priorityRaw, delayCount: m.delayCount, snoozedUntil: m.snoozedUntil,
            pomodoroCount: m.pomodoroCount, sourceRaw: m.sourceRaw, externalIdentifier: m.externalIdentifier
        )
    }

    func makeModel() -> DailyTodo {
        DailyTodo(
            id: id, title: title, notes: notes, createdDate: createdDate,
            plannedForDate: plannedForDate, originalPlannedDate: originalPlannedDate,
            dueDate: dueDate, completedDate: completedDate,
            status: TodoStatus(rawValue: statusRaw) ?? .planned,
            priority: Priority(rawValue: priorityRaw) ?? .medium,
            delayCount: delayCount, snoozedUntil: snoozedUntil, pomodoroCount: pomodoroCount,
            source: TodoSource(rawValue: sourceRaw) ?? .local, externalIdentifier: externalIdentifier
        )
    }
}

/// JSON (de)serialization + the Phase-1 store location.
public enum JSONStore {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// `~/Library/Application Support/DayBar/daybar-store.json` (the Phase-1 store).
    public static var legacyFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("DayBar", isDirectory: true)
            .appendingPathComponent("daybar-store.json")
    }

    public static func loadLegacy() -> StoreSnapshotDTO? {
        guard let data = try? Data(contentsOf: legacyFileURL) else { return nil }
        return try? decoder.decode(StoreSnapshotDTO.self, from: data)
    }

    public static func encode(_ snapshot: StoreSnapshotDTO) throws -> Data { try encoder.encode(snapshot) }
    public static func decode(_ data: Data) throws -> StoreSnapshotDTO { try decoder.decode(StoreSnapshotDTO.self, from: data) }
}
