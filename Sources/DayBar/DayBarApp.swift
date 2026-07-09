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
