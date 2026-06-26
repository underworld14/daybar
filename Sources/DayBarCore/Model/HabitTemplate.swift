import Foundation
import SwiftData

/// Recurring habit definition. A new `HabitLog` is materialized each scheduled calendar day by `HabitEngine`.
@Model
public final class HabitTemplate {
    @Attribute(.unique) public var id: UUID = UUID()
    public var title: String = ""
    public var cueText: String = ""
    public var symbolName: String = "circle"
    public var sortOrder: Int = 0
    public var isActive: Bool = true
    public var createdDate: Date = Date.now
    /// Optional anchor hour (0–23). `anchorMinute` is ignored when nil.
    public var anchorHour: Int? = nil
    public var anchorMinute: Int? = nil
    public var notifyEnabled: Bool = false

    public var schedulePresetRaw: String = HabitSchedulePreset.everyDay.rawValue
    /// Bitmask: bit 0 = Sunday … bit 6 = Saturday. Used when preset is `.custom`.
    public var scheduleWeekdayMask: Int = HabitSchedule.allDaysMask
    public var remindersSyncEnabled: Bool = false
    public var externalReminderIdentifier: String? = nil
    public var externalModifiedAt: Date? = nil
    public var remindersCalendarIdentifier: String? = nil

    public init(
        id: UUID = UUID(),
        title: String = "",
        cueText: String = "",
        symbolName: String = "circle",
        sortOrder: Int = 0,
        isActive: Bool = true,
        createdDate: Date = .now,
        anchorHour: Int? = nil,
        anchorMinute: Int? = nil,
        notifyEnabled: Bool = false,
        schedulePresetRaw: String = HabitSchedulePreset.everyDay.rawValue,
        scheduleWeekdayMask: Int = HabitSchedule.allDaysMask,
        remindersSyncEnabled: Bool = false,
        externalReminderIdentifier: String? = nil,
        externalModifiedAt: Date? = nil,
        remindersCalendarIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.cueText = cueText
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.createdDate = createdDate
        self.anchorHour = anchorHour
        self.anchorMinute = anchorMinute
        self.notifyEnabled = notifyEnabled
        self.schedulePresetRaw = schedulePresetRaw
        self.scheduleWeekdayMask = scheduleWeekdayMask
        self.remindersSyncEnabled = remindersSyncEnabled
        self.externalReminderIdentifier = externalReminderIdentifier
        self.externalModifiedAt = externalModifiedAt
        self.remindersCalendarIdentifier = remindersCalendarIdentifier
    }
}

extension HabitTemplate: Identifiable {
    public var schedulePreset: HabitSchedulePreset {
        HabitSchedule.preset(for: self)
    }

    public func isScheduled(on day: Date, calendar: Calendar = .current) -> Bool {
        HabitSchedule.isScheduled(self, on: day, calendar: calendar)
    }
}