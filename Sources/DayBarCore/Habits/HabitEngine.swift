import Foundation

/// Idempotent daily habit materialization. Creates pending `HabitLog` rows for each active
/// template per calendar day, safe to call from every `AppState.refresh()` trigger.
@MainActor
public final class HabitEngine {
    private let store: DataStore
    private let calendar: Calendar

    public init(store: DataStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    /// Materializes missing logs from the last processed day through today (catch-up) and
    /// always ensures today has a row for every active template (handles mid-day adds).
    @discardableResult
    public func materializeIfNeeded(now: Date = .now) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let meta = try? store.appMeta() else { return false }

        let templates = (try? store.activeHabitTemplates()) ?? []
        var changed = false

        if let last = meta.lastHabitMaterializedDay {
            let lastDay = calendar.startOfDay(for: last)
            if lastDay < today {
                var day = DayMath.nextDay(last, calendar: calendar)
                while day <= today {
                    changed = materializeDay(day, templates: templates) || changed
                    let next = DayMath.nextDay(day, calendar: calendar)
                    if next <= day { break }  // defensive: never spin if a day can't advance
                    day = next
                }
            }
        }

        changed = materializeDay(today, templates: templates) || changed
        changed = backfillFromTemplateCreation(templates: templates, through: today) || changed

        if meta.lastHabitMaterializedDay != today {
            meta.lastHabitMaterializedDay = today
            changed = true
        }

        if changed { store.save() }
        return changed
    }

    /// Ensures every active template has logs from its `createdDate` through `through`.
    private func backfillFromTemplateCreation(templates: [HabitTemplate], through today: Date) -> Bool {
        var changed = false
        for template in templates where template.isActive {
            let createdDay = calendar.startOfDay(for: template.createdDate)
            var day = createdDay
            while day <= today {
                changed = materializeDay(day, templates: [template]) || changed
                let next = DayMath.nextDay(day, calendar: calendar)
                if next <= day { break }  // defensive: never spin if a day can't advance
                day = next
            }
        }
        return changed
    }

    private func materializeDay(_ day: Date, templates: [HabitTemplate]) -> Bool {
        let normalizedDay = calendar.startOfDay(for: day)
        let existingTemplateIds = Set(
            (try? store.habitLogs(on: normalizedDay, calendar: calendar))?.map(\.templateId) ?? []
        )
        var changed = false
        for template in templates where template.isActive {
            let createdDay = calendar.startOfDay(for: template.createdDate)
            guard normalizedDay >= createdDay else { continue }
            guard HabitSchedule.isScheduled(template, on: normalizedDay, calendar: calendar) else { continue }
            guard !existingTemplateIds.contains(template.id) else { continue }
            store.insert(HabitLog(templateId: template.id, day: normalizedDay))
            changed = true
        }
        return changed
    }
}