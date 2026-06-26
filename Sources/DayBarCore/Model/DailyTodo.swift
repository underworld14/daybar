import Foundation
import SwiftData

/// A single planned task, persisted with SwiftData. `statusRaw`/`priorityRaw`/`sourceRaw`
/// are the stored source of truth; typed accessors are computed (never both stored). Every
/// stored property has a default/optional so lightweight migration stays safe.
@Model
public final class DailyTodo {
    @Attribute(.unique) public var id: UUID = UUID()
    public var title: String = ""
    public var notes: String = ""
    public var createdDate: Date = Date.now

    /// Normalized start-of-day. Drives today/overdue queries; mutated on reschedule/snooze.
    public var plannedForDate: Date = Date.now
    /// Normalized start-of-day, set once at creation and never mutated. Basis for age.
    public var originalPlannedDate: Date = Date.now

    public var dueDate: Date?
    /// nil == not done; presence doubles as the completion timestamp.
    public var completedDate: Date?

    public var statusRaw: String = TodoStatus.planned.rawValue
    public var priorityRaw: Int = Priority.medium.rawValue
    public var delayCount: Int = 0
    public var snoozedUntil: Date?
    public var pomodoroCount: Int = 0

    public var sourceRaw: String = TodoSource.local.rawValue
    public var externalIdentifier: String?
    /// Last known modification time from EventKit (conflict detection).
    public var externalModifiedAt: Date?

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
