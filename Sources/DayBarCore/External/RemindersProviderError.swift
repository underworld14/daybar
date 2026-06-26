import Foundation

public enum RemindersProviderError: LocalizedError {
    case reminderNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .reminderNotFound(let id):
            return "Reminder not found: \(id)"
        }
    }
}