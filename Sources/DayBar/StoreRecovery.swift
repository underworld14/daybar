import AppKit
import DayBarCore

/// Opens the live store, or, when it can't be opened (for example after a newer DayBar
/// already updated it), explains what happened and lets the user choose. The data is never
/// deleted: "Start with Empty Data" moves it into the Backups folder first.
@MainActor
enum StoreRecovery {
    static func openStore() -> DataStore {
        do {
            return try DataStore.openLive()
        } catch {
            return recover(from: error)
        }
    }

    private static func recover(from error: Error) -> DataStore {
        let directory = PersistencePaths.dayBarDirectory
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "DayBar couldn't open your data"
        alert.informativeText = """
        Your tasks are still on this Mac and haven't been changed. This can happen when a newer \
        version of DayBar already updated them, or when the data file is damaged.

        Install the latest DayBar to open them again. Or start with empty data: your current \
        data moves to the Backups folder first, so nothing is deleted.

        Details: \(error.localizedDescription)
        """
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Show Backups")
        let startEmpty = alert.addButton(withTitle: "Start with Empty Data")
        startEmpty.hasDestructiveAction = true

        switch alert.runModal() {
        case .alertSecondButtonReturn:
            let backups = StoreBackup.backupsDirectory(in: directory)
            try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([backups])
            exit(0)
        case .alertThirdButtonReturn:
            do {
                try StoreBackup.moveStoreAside(in: directory)
                return try DataStore.openLive()
            } catch {
                let failure = NSAlert()
                failure.alertStyle = .critical
                failure.messageText = "DayBar still couldn't start"
                failure.informativeText = "Your data is in the Backups folder inside \(directory.path). Details: \(error.localizedDescription)"
                failure.addButton(withTitle: "Quit")
                failure.runModal()
                exit(1)
            }
        default:
            exit(0)
        }
    }
}
