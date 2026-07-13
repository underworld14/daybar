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
    public var externalModifiedAt: Date?
}

public struct MetaDTO: Codable, Sendable {
    public var lastProcessedDay: Date?
    public var lastHabitMaterializedDay: Date?
}

public struct HabitTemplateDTO: Codable, Sendable {
    public var id: UUID
    public var title: String
    public var cueText: String
    public var symbolName: String
    public var sortOrder: Int
    public var isActive: Bool
    public var createdDate: Date
    public var anchorHour: Int?
    public var anchorMinute: Int?
    public var notifyEnabled: Bool
    public var schedulePresetRaw: String?
    public var scheduleWeekdayMask: Int?
    public var remindersSyncEnabled: Bool?
    public var externalReminderIdentifier: String?
    public var externalModifiedAt: Date?
    public var remindersCalendarIdentifier: String?
}

public struct HabitLogDTO: Codable, Sendable {
    public var id: UUID
    public var templateId: UUID
    public var day: Date
    public var completedAt: Date?
    public var statusRaw: String
}

public struct FocusSessionDTO: Codable, Sendable {
    public var id: UUID
    public var endedAt: Date
    public var minutes: Int
    public var completed: Bool

    public init(id: UUID, endedAt: Date, minutes: Int, completed: Bool) {
        self.id = id
        self.endedAt = endedAt
        self.minutes = minutes
        self.completed = completed
    }
}

public struct ChecklistItemDTO: Codable, Sendable {
    public var id: UUID
    public var todoId: UUID
    public var title: String
    public var isCompleted: Bool
    public var sortOrder: Int

    public init(
        id: UUID,
        todoId: UUID,
        title: String,
        isCompleted: Bool,
        sortOrder: Int
    ) {
        self.id = id
        self.todoId = todoId
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
    }
}

public struct StoreSnapshotDTO: Codable, Sendable {
    public var todos: [TodoDTO]
    public var meta: MetaDTO?
    public var habitTemplates: [HabitTemplateDTO]
    public var habitLogs: [HabitLogDTO]
    /// `nil` when the backup predates focus export — import must preserve live sessions.
    /// Non-`nil` (including `[]`) replaces focus history on restore.
    public var focusSessions: [FocusSessionDTO]?
    /// Local checklist items; missing key (older backups) decodes as `[]`.
    public var checklistItems: [ChecklistItemDTO]

    public init(
        todos: [TodoDTO],
        meta: MetaDTO? = nil,
        habitTemplates: [HabitTemplateDTO] = [],
        habitLogs: [HabitLogDTO] = [],
        focusSessions: [FocusSessionDTO]? = nil,
        checklistItems: [ChecklistItemDTO] = []
    ) {
        self.todos = todos
        self.meta = meta
        self.habitTemplates = habitTemplates
        self.habitLogs = habitLogs
        self.focusSessions = focusSessions
        self.checklistItems = checklistItems
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        todos = try c.decode([TodoDTO].self, forKey: .todos)
        meta = try c.decodeIfPresent(MetaDTO.self, forKey: .meta)
        habitTemplates = try c.decodeIfPresent([HabitTemplateDTO].self, forKey: .habitTemplates) ?? []
        habitLogs = try c.decodeIfPresent([HabitLogDTO].self, forKey: .habitLogs) ?? []
        focusSessions = try c.decodeIfPresent([FocusSessionDTO].self, forKey: .focusSessions)
        checklistItems = try c.decodeIfPresent([ChecklistItemDTO].self, forKey: .checklistItems) ?? []
    }
}

public extension TodoDTO {
    init(_ m: DailyTodo) {
        self.init(
            id: m.id, title: m.title, notes: m.notes, createdDate: m.createdDate,
            plannedForDate: m.plannedForDate, originalPlannedDate: m.originalPlannedDate,
            dueDate: m.dueDate, completedDate: m.completedDate, statusRaw: m.statusRaw,
            priorityRaw: m.priorityRaw, delayCount: m.delayCount, snoozedUntil: m.snoozedUntil,
            pomodoroCount: m.pomodoroCount, sourceRaw: m.sourceRaw, externalIdentifier: m.externalIdentifier,
            externalModifiedAt: m.externalModifiedAt
        )
    }

    func makeModel() -> DailyTodo {
        let todo = DailyTodo(
            id: id, title: title, notes: notes, createdDate: createdDate,
            plannedForDate: plannedForDate, originalPlannedDate: originalPlannedDate,
            dueDate: dueDate, completedDate: completedDate,
            status: TodoStatus(rawValue: statusRaw) ?? .planned,
            priority: Priority(rawValue: priorityRaw) ?? .medium,
            delayCount: delayCount, snoozedUntil: snoozedUntil, pomodoroCount: pomodoroCount,
            source: TodoSource(rawValue: sourceRaw) ?? .local, externalIdentifier: externalIdentifier
        )
        todo.externalModifiedAt = externalModifiedAt
        return todo
    }
}

public extension HabitTemplateDTO {
    init(_ m: HabitTemplate) {
        self.init(
            id: m.id, title: m.title, cueText: m.cueText, symbolName: m.symbolName,
            sortOrder: m.sortOrder, isActive: m.isActive, createdDate: m.createdDate,
            anchorHour: m.anchorHour, anchorMinute: m.anchorMinute, notifyEnabled: m.notifyEnabled,
            schedulePresetRaw: m.schedulePresetRaw,
            scheduleWeekdayMask: m.scheduleWeekdayMask,
            remindersSyncEnabled: m.remindersSyncEnabled,
            externalReminderIdentifier: m.externalReminderIdentifier,
            externalModifiedAt: m.externalModifiedAt,
            remindersCalendarIdentifier: m.remindersCalendarIdentifier
        )
    }

    func makeModel() -> HabitTemplate {
        HabitTemplate(
            id: id, title: title, cueText: cueText, symbolName: symbolName,
            sortOrder: sortOrder, isActive: isActive, createdDate: createdDate,
            anchorHour: anchorHour, anchorMinute: anchorMinute, notifyEnabled: notifyEnabled,
            schedulePresetRaw: schedulePresetRaw ?? HabitSchedulePreset.everyDay.rawValue,
            scheduleWeekdayMask: scheduleWeekdayMask ?? HabitSchedule.allDaysMask,
            remindersSyncEnabled: remindersSyncEnabled ?? false,
            externalReminderIdentifier: externalReminderIdentifier,
            externalModifiedAt: externalModifiedAt,
            remindersCalendarIdentifier: remindersCalendarIdentifier
        )
    }
}

public extension HabitLogDTO {
    init(_ m: HabitLog) {
        self.init(
            id: m.id, templateId: m.templateId, day: m.day,
            completedAt: m.completedAt, statusRaw: m.statusRaw
        )
    }

    func makeModel() -> HabitLog {
        HabitLog(
            id: id, templateId: templateId, day: day, completedAt: completedAt,
            status: HabitDayStatus(rawValue: statusRaw) ?? .pending
        )
    }
}

public extension FocusSessionDTO {
    init(_ m: FocusSession) {
        self.init(id: m.id, endedAt: m.endedAt, minutes: m.minutes, completed: m.completed)
    }

    func makeModel() -> FocusSession {
        FocusSession(id: id, endedAt: endedAt, minutes: minutes, completed: completed)
    }
}

public extension ChecklistItemDTO {
    init(_ m: TodoChecklistItem) {
        self.init(
            id: m.id, todoId: m.todoId, title: m.title,
            isCompleted: m.isCompleted, sortOrder: m.sortOrder
        )
    }

    func makeModel() -> TodoChecklistItem {
        TodoChecklistItem(
            id: id, todoId: todoId, title: title,
            isCompleted: isCompleted, sortOrder: sortOrder
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
