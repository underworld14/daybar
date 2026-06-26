import Foundation

/// Stable fingerprint for habit anchor notification scheduling.
public enum HabitNotifySignature {
    public static func make(
        templates: [HabitTemplate],
        todayLogs: [HabitLog],
        habitNotifyEnabled: Bool
    ) -> String {
        let templatePart = templates
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { t in
                "\(t.id)|\(t.notifyEnabled)|\(t.anchorHour ?? -1)|\(t.anchorMinute ?? -1)|\(t.isActive)"
            }
            .joined(separator: ";")
        let logPart = todayLogs
            .sorted { $0.templateId.uuidString < $1.templateId.uuidString }
            .map { "\($0.templateId)|\($0.statusRaw)" }
            .joined(separator: ";")
        return "\(habitNotifyEnabled)|\(templatePart)|\(logPart)"
    }
}