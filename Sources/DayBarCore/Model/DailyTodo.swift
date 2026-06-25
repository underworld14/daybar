import Foundation

/// A single planned task. Plain `Codable` reference type (JSON-backed for P1 under
/// Command Line Tools; swappable to a SwiftData `@Model` once Xcode is installed —
/// the persisted shape is identical). `statusRaw`/`priorityRaw`/`sourceRaw` are the
/// stored source of truth; typed accessors are computed (never both stored).
public final class DailyTodo: Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var createdDate: Date

    /// Normalized start-of-day. Drives today/overdue queries; mutated on reschedule/snooze.
    public var plannedForDate: Date
    /// Normalized start-of-day, set once at creation and never mutated. Basis for age.
    public var originalPlannedDate: Date

    public var dueDate: Date?
    /// nil == not done; presence doubles as the completion timestamp.
    public var completedDate: Date?

    public var statusRaw: String
    public var priorityRaw: Int
    public var delayCount: Int
    public var snoozedUntil: Date?
    public var pomodoroCount: Int

    public var sourceRaw: String
    public var externalIdentifier: String?

    public init(
        id: UUID = UUID(),
        title: String = "",
        notes: String = "",
        createdDate: Date = .now,
        plannedForDate: Date,
        originalPlannedDate: Date? = nil,
        dueDate: Date? = nil,
        completedDate: Date? = nil,
        status: TodoStatus = .planned,
        priority: Priority = .medium,
        delayCount: Int = 0,
        snoozedUntil: Date? = nil,
        pomodoroCount: Int = 0,
        source: TodoSource = .local,
        externalIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdDate = createdDate
        self.plannedForDate = plannedForDate
        self.originalPlannedDate = originalPlannedDate ?? plannedForDate
        self.dueDate = dueDate
        self.completedDate = completedDate
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.delayCount = delayCount
        self.snoozedUntil = snoozedUntil
        self.pomodoroCount = pomodoroCount
        self.sourceRaw = source.rawValue
        self.externalIdentifier = externalIdentifier
    }
}

public extension DailyTodo {
    var status: TodoStatus {
        get { TodoStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }
    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
    var source: TodoSource {
        get { TodoSource(rawValue: sourceRaw) ?? .local }
        set { sourceRaw = newValue.rawValue }
    }

    var isCompleted: Bool { completedDate != nil }

    /// Days since the task was first planned (clamped at 0), computed live from the
    /// immutable `originalPlannedDate` so no per-row daily writes are needed.
    func carryOverAgeInDays(asOf now: Date = .now, calendar: Calendar = .current) -> Int {
        max(0, DayMath.dayDifference(from: originalPlannedDate, to: now, calendar: calendar))
    }

    /// Escalation tier for this task right now. Completed tasks never escalate.
    func escalationTier(
        asOf now: Date = .now,
        thresholds: EscalationThresholds = .gentle,
        calendar: Calendar = .current
    ) -> EscalationTier {
        guard !isCompleted else { return .onPlan }
        return EscalationModel.tier(forAgeInDays: carryOverAgeInDays(asOf: now, calendar: calendar), thresholds: thresholds)
    }

    func ageLabel(asOf now: Date = .now, calendar: Calendar = .current) -> String? {
        EscalationModel.ageLabel(forAgeInDays: carryOverAgeInDays(asOf: now, calendar: calendar))
    }
}
