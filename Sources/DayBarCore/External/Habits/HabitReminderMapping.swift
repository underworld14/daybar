import Foundation
import EventKit

/// Pure mapping between `HabitReminderDTO`, `HabitTemplate`, and `HabitLog`.
public enum HabitReminderMapping {
    public static let notesPrefix = "daybar:habit:"

    public static func notesMarker(templateId: UUID) -> String {
        notesPrefix + templateId.uuidString
    }

    public static func parseTemplateId(from notes: String) -> UUID? {
        guard let range = notes.range(of: notesPrefix) else { return nil }
        let idString = String(notes[range.upperBound...]).split(separator: "\n").first.map(String.init) ?? ""
        return UUID(uuidString: idString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func buildNotes(templateId: UUID, cueText: String) -> String {
        var parts = [notesMarker(templateId: templateId)]
        let trimmedCue = cueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCue.isEmpty { parts.append(trimmedCue) }
        return parts.joined(separator: "\n")
    }

    public static func dueDateComponents(
        for template: HabitTemplate,
        referenceDay: Date,
        calendar: Calendar
    ) -> DateComponents {
        let day = calendar.startOfDay(for: referenceDay)
        let hour = template.anchorHour ?? 9
        let minute = template.anchorMinute ?? 0
        return calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        )
    }

    public static func recurrenceRule(
        preset: HabitSchedulePreset,
        weekdayMask: Int
    ) -> EKRecurrenceRule {
        switch preset {
        case .everyDay:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekdays, .weekends, .custom:
            let mask = preset == .custom ? weekdayMask : HabitSchedule.maskForPreset(preset)
            let days = HabitSchedule.eventKitWeekdays(mask: mask).compactMap { weekday -> EKRecurrenceDayOfWeek? in
                guard let ekDay = EKWeekday(rawValue: weekday) else { return nil }
                return EKRecurrenceDayOfWeek(ekDay)
            }
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: days,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )
        }
    }

    public static func dto(from template: HabitTemplate, calendar: Calendar, referenceDay: Date) -> HabitReminderDTO {
        let due = calendar.date(from: dueDateComponents(for: template, referenceDay: referenceDay, calendar: calendar))
        return HabitReminderDTO(
            externalIdentifier: template.externalReminderIdentifier ?? "",
            templateId: template.id,
            title: template.title,
            notes: buildNotes(templateId: template.id, cueText: template.cueText),
            dueDate: due,
            isCompleted: false,
            calendarIdentifier: template.remindersCalendarIdentifier ?? "",
            modifiedAt: template.externalModifiedAt,
            schedulePreset: HabitSchedule.preset(for: template),
            weekdayMask: HabitSchedule.weekdayMask(for: template)
        )
    }

    public static func applyMetadata(_ dto: HabitReminderDTO, to template: HabitTemplate) {
        template.title = dto.title
        template.externalModifiedAt = dto.modifiedAt
        template.remindersCalendarIdentifier = dto.calendarIdentifier.isEmpty
            ? template.remindersCalendarIdentifier
            : dto.calendarIdentifier
        if let parsedId = parseTemplateId(from: dto.notes), parsedId == template.id {
            let cue = dto.notes
                .replacingOccurrences(of: notesMarker(templateId: template.id), with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cue.isEmpty { template.cueText = cue }
        }
    }

    public static func applyCompletion(
        remoteCompleted: Bool,
        completionDate: Date?,
        to log: HabitLog,
        today: Date
    ) {
        if remoteCompleted, !log.isCompleted {
            log.status = .completed
            log.completedAt = completionDate ?? today
        } else if !remoteCompleted, log.isCompleted {
            log.status = .pending
            log.completedAt = nil
        }
    }

    public static func shouldApplyRemote(_ dto: HabitReminderDTO, over template: HabitTemplate) -> Bool {
        guard let remote = dto.modifiedAt, let local = template.externalModifiedAt else { return true }
        return remote >= local
    }
}