import Foundation

public extension Priority {
    /// One-click cycle used by the priority flag: none → low → medium → high → none.
    var next: Priority {
        switch self {
        case .none: return .low
        case .low: return .medium
        case .medium: return .high
        case .high: return .none
        }
    }

    /// The opposite direction (VoiceOver decrement), never wrapping past the ends.
    var lower: Priority {
        switch self {
        case .none, .low: return .none
        case .medium: return .low
        case .high: return .medium
        }
    }

    /// The step up (VoiceOver increment), never wrapping past high.
    var higher: Priority {
        switch self {
        case .none: return .low
        case .low: return .medium
        case .medium, .high: return .high
        }
    }

    /// Filled bars in the priority glyph: 0 (none) … 3 (high).
    var level: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    /// Keyboard digit shortcut → priority (0 none … 3 high).
    init?(level: Int) {
        switch level {
        case 0: self = .none
        case 1: self = .low
        case 2: self = .medium
        case 3: self = .high
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}
