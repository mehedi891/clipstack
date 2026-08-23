import Foundation
import ServiceManagement

/// Start-at-login, via the modern SMAppService API (macOS 13+).
///
/// The system, not our preferences file, is the source of truth: the user can
/// revoke this in System Settings › General › Login Items at any time.
public enum LaunchAtLogin {

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting state, which may differ from what was requested if
    /// the user has denied the app in Login Items.
    @discardableResult
    public static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Clipstack: launch at login %@ failed: %@", enabled ? "enable" : "disable", "\(error)")
        }
        return isEnabled
    }
}
