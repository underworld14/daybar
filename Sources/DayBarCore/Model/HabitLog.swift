import Foundation
import SwiftData

/// One checkable instance of a habit for a single calendar day (`day` = normalized start-of-day).
@Model
public final class HabitLog {
    @Attribute(.unique) public var id: UUID = UUID()
    public var templateId: UUID = UUID()
    public var day: Date = Date.now
    public var completedAt: Date? = nil
    public var statusRaw: String = HabitDayStatus.pending.rawValue

    public init(
        id: UUID = UUID(),
        templateId: UUID,
        day: Date,
        completedAt: Date? = nil,
        status: HabitDayStatus = .pending
    ) {
        self.id = id
        self.templateId = templateId
        self.day = day
        self.completedAt = completedAt
        self.statusRaw = status.rawValue
    }
}

public extension HabitLog {
    var status: HabitDayStatus {
        get { HabitDayStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var isCompleted: Bool { status == .completed }
}

/// Template + today's log, joined for the UI.
public struct TodayHabit: Identifiable {
    public let template: HabitTemplate
    public let log: HabitLog
    public var id: UUID { log.id }

    public init(template: HabitTemplate, log: HabitLog) {
        self.template = template
        self.log = log
    }
}