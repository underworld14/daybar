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
                    day = DayMath.nextDay(day, calendar: calendar)
                }
            }
        }

        changed = materializeDay(today, templates: templates) || changed

        if meta.lastHabitMaterializedDay != today {
            meta.lastHabitMaterializedDay = today
            changed = true
        }

        if changed { store.save() }
        return changed
    }

    private func materializeDay(_ day: Date, templates: [HabitTemplate]) -> Bool {
        var changed = false
        for template in templates where template.isActive {
            let createdDay = calendar.startOfDay(for: template.createdDate)
            guard day >= createdDay else { continue }
            if !(store.hasHabitLog(templateId: template.id, day: day, calendar: calendar)) {
                store.insert(HabitLog(templateId: template.id, day: day))
                changed = true
            }
        }
        return changed
    }
}