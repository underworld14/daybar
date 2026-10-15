import SwiftUI
import DayBarCore

/// High → None priority choices with a checkmark on the current one; used in every
/// priority submenu and the flag's right-click menu.
struct PriorityMenuItems: View {
    let current: Priority
    let onSet: (Priority) -> Void

    var body: some View {
        ForEach([Priority.high, .medium, .low, .none], id: \.self) { level in
            Button {
                onSet(level)
            } label: {
                if level == current {
                    Label(level.displayName, systemImage: "checkmark")
                } else {
                    Text(level.displayName)
                }
            }
        }
    }
}
