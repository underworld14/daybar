import SwiftUI
import DayBarCore

@main
struct DayBarApp: App {
    @State private var appState: AppState

    init() {
        AppKitBridge.setAccessoryActivationPolicy()
        let store = DataStore()
        _appState = State(initialValue: AppState(store: store))
    }

    var body: some Scene {
        MenuBarScene(appState: appState)
    }
}

/// Nested `Scene` struct that holds the state — the documented workaround for the
/// `MenuBarExtra` content-body-not-re-rendering bug. Uses the `.window` style so the
/// panel can host interactive controls (list, checkboxes, quick-add field).
struct MenuBarScene: Scene {
    let appState: AppState

    var body: some Scene {
        MenuBarExtra {
            TodayView()
                .environment(appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Dynamic menu-bar label: a focus glyph + coarse minutes while a Pomodoro runs, and an
/// amber overdue count. Rendered inside the SwiftUI label closure (not via AppKit drawing).
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
