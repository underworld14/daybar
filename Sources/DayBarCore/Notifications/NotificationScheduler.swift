import Foundation
import Observation
import UserNotifications

/// Pure scheduling / presentation decisions shared by notification code and unit tests.
public enum NotificationScheduling {
    public static let remindersThread = "daybar.reminders"
    public static let focusThread = "daybar.focus"

    /// Next upcoming 14:00 when there are aging tasks; `nil` when none.
    /// After 14:00, returns tomorrow 14:00 (no immediate catch-up on open).
    public static func backlogFireDate(
        agingCount: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard agingCount > 0 else { return nil }
        guard let todayAtTwo = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now) else {
            return nil
        }
        if now < todayAtTwo { return todayAtTwo }
        return calendar.date(byAdding: .day, value: 1, to: todayAtTwo)
    }

    public static func backlogDeliveryInterval(
        agingCount: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TimeInterval? {
        guard let fireDate = backlogFireDate(agingCount: agingCount, now: now, calendar: calendar) else {
            return nil
        }
        let interval = fireDate.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        return interval
    }

    /// Foreground presentation: suppress banner/sound for reminders while the panel is open;
    /// phase-end may still banner. Sound follows quiet-hours / Focus gating via `allowSound`.
    public static func willPresentOptions(
        identifier: String,
        panelVisible: Bool,
        allowSound: Bool
    ) -> UNNotificationPresentationOptions {
        let isPhaseEnd = identifier == NotificationScheduler.ID.phaseEnd
        if panelVisible && !isPhaseEnd {
            return [.list]
        }
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if allowSound {
            options.insert(.sound)
        }
        return options
    }

    public static func habitAnchorTemplates(
        templates: [HabitTemplate],
        todayLogs: [HabitLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [HabitTemplate] {
        let completed = Set(todayLogs.filter { $0.isCompleted || $0.status == .skipped }.map(\.templateId))
        let today = calendar.startOfDay(for: now)
        return templates.filter { template in
            template.notifyEnabled
                && template.isActive
                && template.isScheduled(on: today, calendar: calendar)
                && !completed.contains(template.id)
                && template.anchorHour != nil
                && template.anchorMinute != nil
        }
    }
}

/// Wraps `UNUserNotificationCenter`: morning/evening reminders, the Pomodoro phase-end banner,
/// and a once-daily backlog nudge. Scheduling is gated by `authorized`, so everything degrades
/// gracefully when notification permission is denied.
@MainActor
@Observable
public final class NotificationScheduler {
    private var center: UNUserNotificationCenter? {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    public private(set) var authorized = false
    public var onAuthorizationGranted: (() -> Void)?

    public init() {}

    /// Identifiers (stable so they can be removed/replaced).
    public enum ID {
        public static let morning = "morning.plan"
        public static let evening = "evening.review"
        public static let phaseEnd = "pomodoro.phaseEnd"
        public static let backlog = "backlog.nudge"
        public static let habitPrefix = "habit.anchor."
        public static let weeklyDigest = "weekly.digest"
    }

    // MARK: - Authorization

    public func requestAuthorization() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.authorized = granted
                if granted {
                    self?.rescheduleRepeating()
                    self?.onAuthorizationGranted?()
                }
            }
        }
    }

    /// Re-checks the live system permission (the user may have granted/revoked it in
    /// System Settings after the initial prompt), so Settings can reflect reality rather
    /// than a stale value captured only once at launch.
    public func refreshAuthorizationStatus() {
        guard let center else { return }
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Repeating reminders

    public func rescheduleRepeating() {
        guard let center else { return }
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
        guard let center else { return }
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = Preferences.shouldPlayAudibleAlerts() ? .default : nil
        content.threadIdentifier = NotificationScheduling.remindersThread
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Pomodoro phase end (silent banner; AlertSoundPlayer provides the audio)

    public func postPhaseEndBanner(finished: PomodoroPhase) {
        guard let center, authorized, Preferences.phaseEndNotify else { return }
        let content = UNMutableNotificationContent()
        if finished == .work {
            content.title = "Focus done"
            content.body = "Time for a break."
        } else {
            content.title = "Break over"
            content.body = "Back to focus."
        }
        content.sound = nil
        content.threadIdentifier = NotificationScheduling.focusThread
        center.add(UNNotificationRequest(identifier: ID.phaseEnd, content: content, trigger: nil))
    }

    // MARK: - Habit anchor reminders (per-template, skipped when already completed today)

    public func rescheduleHabitAnchors(
        templates: [HabitTemplate],
        todayLogs: [HabitLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        guard let center else { return }
        center.getPendingNotificationRequests { [weak self] requests in
            let habitIDs = requests.map(\.identifier).filter { $0.hasPrefix(ID.habitPrefix) }
            Task { @MainActor in
                self?.center?.removePendingNotificationRequests(withIdentifiers: habitIDs)
                self?.scheduleHabitAnchors(templates: templates, todayLogs: todayLogs, now: now, calendar: calendar)
            }
        }
    }

    private func scheduleHabitAnchors(
        templates: [HabitTemplate],
        todayLogs: [HabitLog],
        now: Date,
        calendar: Calendar
    ) {
        guard authorized, Preferences.habitNotifyEnabled else { return }
        for template in NotificationScheduling.habitAnchorTemplates(
            templates: templates,
            todayLogs: todayLogs,
            now: now,
            calendar: calendar
        ) {
            guard let hour = template.anchorHour, let minute = template.anchorMinute else { continue }
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
        guard let center else { return }
        center.removePendingNotificationRequests(withIdentifiers: [ID.backlog])
        guard authorized, Preferences.backlogNotify else { return }
        guard let deliveryInterval = NotificationScheduling.backlogDeliveryInterval(
            agingCount: agingCount,
            now: now,
            calendar: calendar
        ) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Tasks piling up"
        content.body = agingCount == 1
            ? "1 task has been waiting a few days — reschedule or drop it?"
            : "\(agingCount) tasks have been waiting a few days — reschedule or drop them?"
        content.sound = Preferences.shouldPlayAudibleAlerts() ? .default : nil
        content.threadIdentifier = NotificationScheduling.remindersThread
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: deliveryInterval, repeats: false)
        center.add(UNNotificationRequest(identifier: ID.backlog, content: content, trigger: trigger))
    }

    // MARK: - Weekly digest

    public func postWeeklyDigest(
        tasksCompleted: Int,
        habitsCompleted: Int,
        focusSessions: Int,
        agingTasks: Int
    ) {
        guard let center, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your week in DayBar"
        content.body = "\(tasksCompleted) tasks · \(habitsCompleted) habits · \(focusSessions) focus · \(agingTasks) aging"
        content.sound = Preferences.shouldPlayAudibleAlerts() ? .default : nil
        content.threadIdentifier = NotificationScheduling.remindersThread
        center.add(UNNotificationRequest(identifier: ID.weeklyDigest, content: content, trigger: nil))
    }
}
