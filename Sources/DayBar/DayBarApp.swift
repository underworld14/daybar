import SwiftUI
import DayBarCore

@main
struct DayBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The whole UI is an NSStatusItem + NSPanel driven by AppDelegate (see
        // MenuBarController.swift). This empty Settings scene just satisfies the `App`
        // protocol; it is never shown.
        Settings { EmptyView() }
    }
}

/// Dynamic menu-bar label: a focus glyph + coarse minutes while a Pomodoro runs, and an
/// amber overdue count. Hosted in the status-item button via `PassthroughHostingView`.
struct MenuBarLabel: View {
    var appState: AppState

    var body: some View {
        let pomo = appState.pomodoro
        HStack(spacing: 3) {
            if pomo.phase != .idle {
                Image(systemName: pomo.phase.isBreak ? "cup.and.saucer.fill" : "timer")
                if pomo.isRunning {
                    Text("\(pomo.remainingMinutesCoarse)m")
                }
            } else {
                Image(systemName: "checklist")
            }
            if appState.overdueCount > 0 {
                Text("\(appState.overdueCount)")
            }
        }
    }
}
