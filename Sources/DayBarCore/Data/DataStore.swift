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
        let schema = Schema([
            DailyTodo.self, AppMeta.self, FocusSession.self, DayLog.self,
            HabitTemplate.self, HabitLog.self,
        ])
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

    /// Last error from `save()`, if any. Cleared on the next successful save.
    public private(set) var lastSaveError: String?
    /// Wall-clock time of the most recent successful save (nil until first success).
    public private(set) var lastSuccessfulSaveAt: Date?

    /// Explicit save — SwiftData autosave can fail silently, so mutations call this.
    /// Returns `true` when there was nothing to save or the save succeeded.
    @discardableResult
    public func save() -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            lastSaveError = nil
            lastSuccessfulSaveAt = Date()
            return true
        } catch {
            lastSaveError = error.localizedDescription
            print("DayBar: save error: \(error)")
            return false
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

    public func todo(externalIdentifier: String) throws -> DailyTodo? {
        let id = externalIdentifier
        let predicate = #Predicate<DailyTodo> { $0.externalIdentifier == id }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    public func remindersTodos() throws -> [DailyTodo] {
        let source = TodoSource.reminders.rawValue
        let predicate = #Predicate<DailyTodo> { $0.sourceRaw == source }
        return try context.fetch(FetchDescriptor(predicate: predicate))
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

    /// Completed, non-dropped todos whose `completedDate` falls in `[start, end)`.
    public func completedTodos(in range: Range<Date>) throws -> [DailyTodo] {
        let start = range.lowerBound, end = range.upperBound
        let dropped = TodoStatus.dropped.rawValue
        let predicate = #Predicate<DailyTodo> { todo in
            todo.completedDate != nil && todo.statusRaw != dropped
        }
        let fetched = try context.fetch(FetchDescriptor(predicate: predicate))
        return fetched
            .filter { todo in
                guard let completed = todo.completedDate else { return false }
                return completed >= start && completed < end
            }
            .sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
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

    /// Day logs whose `day` falls in `[range.lowerBound, range.upperBound)` — used by
    /// the mood analytics buckets (no re-inference; scores are read straight off the
    /// stored `moodTagRaw`).
    public func dayLogs(in range: Range<Date>) throws -> [DayLog] {
        let start = range.lowerBound, end = range.upperBound
        let predicate = #Predicate<DayLog> { $0.day >= start && $0.day < end }
        return try context.fetch(FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.day)]))
    }

    @discardableResult
    public func upsertDayLog(
        day: Date,
        reflection: String,
        plannedCount: Int,
        completedCount: Int,
        moodTag: MoodTag? = nil,
        moodSource: MoodSource = .none,
        calendar: Calendar = .current
    ) -> DayLog {
        let start = calendar.startOfDay(for: day)
        if let existing = (try? dayLog(for: start, calendar: calendar)) ?? nil {
            existing.reflection = reflection
            existing.plannedCount = plannedCount
            existing.completedCount = completedCount
            existing.moodTag = moodTag
            existing.moodSource = moodSource
            save()
            return existing
        }
        let log = DayLog(
            day: start, reflection: reflection, plannedCount: plannedCount, completedCount: completedCount,
            moodTag: moodTag, moodSource: moodSource
        )
        context.insert(log)
        save()
        return log
    }

    // MARK: - Habits

    @discardableResult
    public func insert(_ template: HabitTemplate) -> HabitTemplate {
        context.insert(template)
        return template
    }

    @discardableResult
    public func insert(_ log: HabitLog) -> HabitLog {
        if hasHabitLog(templateId: log.templateId, day: log.day) {
            return log
        }
        context.insert(log)
        return log
    }

    public func delete(_ template: HabitTemplate) {
        context.delete(template)
    }

    public func allHabitTemplates() throws -> [HabitTemplate] {
        try context.fetch(FetchDescriptor<HabitTemplate>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdDate)]
        ))
    }

    public func activeHabitTemplates() throws -> [HabitTemplate] {
        try allHabitTemplates().filter(\.isActive)
    }

    public func habitTemplate(id: UUID) throws -> HabitTemplate? {
        let predicate = #Predicate<HabitTemplate> { $0.id == id }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    public func habitTemplate(externalReminderIdentifier: String) throws -> HabitTemplate? {
        let ext = externalReminderIdentifier
        let predicate = #Predicate<HabitTemplate> { $0.externalReminderIdentifier == ext }
        return try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    public func syncedHabitTemplates() throws -> [HabitTemplate] {
        try allHabitTemplates().filter { $0.externalReminderIdentifier != nil }
    }

    public func habitLogs(on day: Date, calendar: Calendar = .current) throws -> [HabitLog] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = #Predicate<HabitLog> { $0.day >= start && $0.day < end }
        return try context.fetch(FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.day)]))
    }

    public func habitLogs(in range: Range<Date>) throws -> [HabitLog] {
        let start = range.lowerBound, end = range.upperBound
        let predicate = #Predicate<HabitLog> { $0.day >= start && $0.day < end }
        return try context.fetch(FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.day)]))
    }

    public func habitLogs(
        since startDay: Date,
        through endDay: Date,
        calendar: Calendar = .current
    ) throws -> [HabitLog] {
        let start = calendar.startOfDay(for: startDay)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDay)) ?? start
        return try habitLogs(in: start..<end)
    }

    public func allHabitLogs() throws -> [HabitLog] {
        try context.fetch(FetchDescriptor<HabitLog>(sortBy: [SortDescriptor(\.day)]))
    }

    public func hasHabitLog(templateId: UUID, day: Date, calendar: Calendar = .current) -> Bool {
        let logs = (try? habitLogs(on: day, calendar: calendar)) ?? []
        return logs.contains { $0.templateId == templateId }
    }

    /// Active templates joined with today's logs, sorted by `sortOrder`.
    public func todayHabits(on day: Date, calendar: Calendar = .current) throws -> [TodayHabit] {
        let templates = try activeHabitTemplates()
        let logs = try habitLogs(on: day, calendar: calendar)
        let byTemplate = Dictionary(uniqueKeysWithValues: logs.map { ($0.templateId, $0) })
        return templates.compactMap { template in
            guard let log = byTemplate[template.id] else { return nil }
            return TodayHabit(template: template, log: log)
        }
    }

    // MARK: - JSON export / import

    public func exportSnapshot() -> StoreSnapshotDTO {
        let todos = (try? allTodos()) ?? []
        let meta = try? appMeta()
        let habits = (try? allHabitTemplates()) ?? []
        let habitLogs = (try? allHabitLogs()) ?? []
        return StoreSnapshotDTO(
            todos: todos.map(TodoDTO.init),
            meta: MetaDTO(
                lastProcessedDay: meta?.lastProcessedDay,
                lastHabitMaterializedDay: meta?.lastHabitMaterializedDay
            ),
            habitTemplates: habits.map(HabitTemplateDTO.init),
            habitLogs: habitLogs.map(HabitLogDTO.init)
        )
    }

    /// Replace ALL todos/habits with the snapshot's contents (used by Settings "Import").
    /// Destructive by design — the caller should confirm with the user first.
    /// Deletes and re-inserts are committed in a **single** save so a crash mid-import
    /// leaves the previous on-disk store intact (SwiftData only persists on `save()`).
    @discardableResult
    public func importSnapshot(_ snapshot: StoreSnapshotDTO) -> Bool {
        for existing in (try? allTodos()) ?? [] { context.delete(existing) }
        for existing in (try? allHabitTemplates()) ?? [] { context.delete(existing) }
        for existing in (try? allHabitLogs()) ?? [] { context.delete(existing) }
        for dto in snapshot.todos { context.insert(dto.makeModel()) }
        for dto in snapshot.habitTemplates { context.insert(dto.makeModel()) }
        for dto in snapshot.habitLogs { context.insert(dto.makeModel()) }
        if let meta = try? appMeta() {
            meta.lastProcessedDay = snapshot.meta?.lastProcessedDay
            meta.lastHabitMaterializedDay = snapshot.meta?.lastHabitMaterializedDay
        }
        return save()
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
