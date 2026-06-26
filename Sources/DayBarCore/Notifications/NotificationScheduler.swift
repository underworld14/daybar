import Foundation
import UserNotifications

/// Wraps `UNUserNotificationCenter`: morning/evening reminders, the Pomodoro phase-end banner,
/// and a once-daily backlog nudge. Scheduling is gated by `authorized`, so everything degrades
/// gracefully when notification permission is denied.
@MainActor
public final class NotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    public private(set) var authorized = false

    public init() {}

    /// Identifiers (stable so they can be removed/replaced).
    private enum ID {
        static let morning = "morning.plan"
        static let evening = "evening.review"
        static let phaseEnd = "pomodoro.phaseEnd"
        static let backlog = "backlog.nudge"
        static let habitPrefix = "habit.anchor."
    }

    // MARK: - Authorization

    public func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.authorized = granted
                if granted { self?.rescheduleRepeating() }
            }
        }
    }

    // MARK: - Repeating reminders

    public func rescheduleRepeating() {
        center.removePendingNotificationRequests(withIdentifiers: [ID.morning, ID.evening])
        guard authorized else { return }
        if Preferences.morningEnabled {
            addCalendar(id: ID.morning, hour: Preferences.morningHour, minute: Preferences.morningMinute,
                        title: "Plan your day", body: "What matters today? Add your tasks.")
        }
        if Preferences.eveningEnabled {
            addCalendar(id: ID.evening, hour: Preferences.eveningHour, minute: Preferences.eveningMinute,
                        title: "Review your day", body: "Did you finish what you planned?")
        }
    }

    private func addCalendar(id: String, hour: Int, minute: Int, title: String, body: String) {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Pomodoro phase end (silent banner; the chosen NSSound provides the audio)

    public func postPhaseEndBanner(finished: PomodoroPhase) {
        guard authorized, Preferences.phaseEndNotify else { return }
        let content = UNMutableNotificationContent()
        if finished == .work {
            content.title = "Focus done"
            content.body = "Time for a break."
        } else {
            content.title = "Break over"
            content.body = "Back to focus."
        }
        content.sound = nil
        center.add(UNNotificationRequest(identifier: ID.phaseEnd, content: content, trigger: nil))
    }

    // MARK: - Habit anchor reminders (per-template, skipped when already completed today)

    public func rescheduleHabitAnchors(templates: [HabitTemplate], todayLogs: [HabitLog]) {
        center.getPendingNotificationRequests { [weak self] requests in
            let habitIDs = requests.map(\.identifier).filter { $0.hasPrefix(ID.habitPrefix) }
            Task { @MainActor in
                self?.center.removePendingNotificationRequests(withIdentifiers: habitIDs)
                self?.scheduleHabitAnchors(templates: templates, todayLogs: todayLogs)
            }
        }
    }

    private func scheduleHabitAnchors(templates: [HabitTemplate], todayLogs: [HabitLog]) {
        guard authorized, Preferences.habitNotifyEnabled else { return }
        let completed = Set(todayLogs.filter(\.isCompleted).map(\.templateId))
        for template in templates where template.notifyEnabled && template.isActive {
            guard !completed.contains(template.id),
                  let hour = template.anchorHour,
                  let minute = template.anchorMinute else { continue }
            let body: String
            if template.cueText.isEmpty {
                body = "Time for: \(template.title)"
            } else {
                body = "\(template.cueText) — \(template.title)"
            }
            addCalendar(
                id: ID.habitPrefix + template.id.uuidString,
                hour: hour,
                minute: minute,
                title: "Habit reminder",
                body: body
            )
        }
    }

    // MARK: - Backlog nudge (once/day, state-gated, idempotent)

    public func updateBacklogNudge(agingCount: Int, now: Date = .now, calendar: Calendar = .current) {
        center.removePendingNotificationRequests(withIdentifiers: [ID.backlog])
        guard authorized, Preferences.backlogNotify, agingCount > 0 else { return }
        guard let fireDate = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Tasks piling up"
        content.body = agingCount == 1
            ? "1 task has been waiting a few days — reschedule or drop it?"
            : "\(agingCount) tasks have been waiting a few days — reschedule or drop them?"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireDate.timeIntervalSince(now)), repeats: false)
        center.add(UNNotificationRequest(identifier: ID.backlog, content: content, trigger: trigger))
    }
}
