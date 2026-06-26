import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the launch-at-login toggle. Drive the UI
/// from `status`/`isEnabled` rather than a stored Bool, so it reflects reality (the user can
/// disable the login item from System Settings).
@MainActor
public enum LaunchAtLogin {
    public static var status: SMAppService.Status { SMAppService.mainApp.status }

    public static var isEnabled: Bool { status == .enabled }

    /// `.requiresApproval` means the user turned it off in System Settings > Login Items.
    public static var requiresApproval: Bool { status == .requiresApproval }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
