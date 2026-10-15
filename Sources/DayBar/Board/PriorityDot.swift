import SwiftUI
import DayBarCore

/// Small colored dot mirroring the panel's priority ordering (high > medium > low > none).
struct PriorityDot: View {
    let priority: Priority

    var body: some View {
        Group {
            if priority != .none {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .help(helpText)
            }
        }
    }

    private var color: Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .secondary
        case .none: return .clear
        }
    }

    private var helpText: String {
        switch priority {
        case .high: return "High priority"
        case .medium: return "Medium priority"
        case .low: return "Low priority"
        case .none: return "No priority"
        }
    }
}
