import AppKit
import SwiftUI
import DayBarCore

@main
struct DayBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var appState: AppState

    init() {
        // One shared AppState for the tray panel and the main window. Accessing `delegate`
        // instantiates the adaptor's object so the injection lands before launch finishes.
        let state = AppState(store: DataStore())
        _appState = State(initialValue: state)
        delegate.appState = state
    }

    var body: some Scene {
        // The whole UI is an NSStatusItem + NSPanel driven by AppDelegate (see
        // MenuBarController.swift); the main window is AppKit-owned too. This empty
        // Settings scene just satisfies the `App` protocol; it is never shown. The
        // main menu is declared here because SwiftUI owns `NSApp.mainMenu` and
        // rebuilds it on activation-policy changes.
        Settings { EmptyView() }
            .commands { DayBarCommands(appState: appState) }
    }
}

/// Main menu for window mode. SwiftUI only shows the menu bar while the app is
/// `.regular` (i.e. the main window is open).
struct DayBarCommands: Commands {
    let appState: AppState

    var body: some Commands {
        // `.newItem` anchors these at the top of the auto-generated File menu
        // (between the app menu and the system Edit menu).
        CommandGroup(replacing: .newItem) {
            Button("New Task") { appState.windowAddTaskFocusSignal += 1 }
                .keyboardShortcut("n")
            Button("New Note") { appState.windowNewNoteSignal += 1 }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
        }
        CommandGroup(after: .sidebar) {
            Button("Show/Hide Inspector") { appState.sendWindowCommand(.toggleInspector) }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
        CommandMenu("Task") {
            Button("Complete") { appState.sendWindowCommand(.completeSelected) }
                .keyboardShortcut("k")
            Button("Start / Stop") { appState.sendWindowCommand(.toggleStartSelected) }
                .keyboardShortcut("k", modifiers: [.command, .option])
            Menu("Priority") {
                Button("High") { appState.sendWindowCommand(.setPriority(.high)) }
                    .keyboardShortcut("3")
                Button("Medium") { appState.sendWindowCommand(.setPriority(.medium)) }
                    .keyboardShortcut("2")
                Button("Low") { appState.sendWindowCommand(.setPriority(.low)) }
                    .keyboardShortcut("1")
                Button("None") { appState.sendWindowCommand(.setPriority(.none)) }
                    .keyboardShortcut("0")
            }
            Divider()
            Button("Move to Today") { appState.sendWindowCommand(.moveSelectedToToday) }
                .keyboardShortcut("t", modifiers: [.command, .control])
            Button("Move to Tomorrow") { appState.sendWindowCommand(.moveSelectedToTomorrow) }
                .keyboardShortcut("t", modifiers: [.command, .control, .shift])
            Divider()
            // No ⌘⌫ equivalent: it would fire while editing text in the inspector. Plain
            // Delete drops when the board has focus.
            Button("Drop") { appState.sendWindowCommand(.dropSelected) }
        }
        CommandGroup(after: .windowArrangement) {
            Button("Open DayBar Window") {
                NotificationCenter.default.post(name: AppDelegate.openMainWindowNotification, object: nil)
            }
        }
        CommandGroup(after: .help) {
            Button("DayBar Website") {
                if let url = URL(string: "https://underworld14.github.io/daybar/") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
