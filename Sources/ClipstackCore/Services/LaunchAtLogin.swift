import Foundation
import ServiceManagement

/// Start-at-login.
///
/// macOS 13 and newer use `SMAppService`, where the system rather than our
/// preferences file is the source of truth: the user can revoke this in System
/// Settings › General › Login Items at any time.
///
/// macOS 12 has no such API — `SMAppService` is 13+, and the API it replaced
/// needs a separate helper application embedded in the bundle. A launch agent
/// does the same job with a file: `launchd` reads `~/Library/LaunchAgents` at
/// login and starts what it finds there.
public enum LaunchAtLogin {

    public static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return LaunchAgent.isInstalled
    }

    /// Returns the resulting state, which may differ from what was requested if
    /// the user has denied the app in Login Items.
    @discardableResult
    public static func set(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Clipstack: launch at login %@ failed: %@", enabled ? "enable" : "disable", "\(error)")
            }
        } else {
            LaunchAgent.set(enabled)
        }
        return isEnabled
    }
}

/// The macOS 12 fallback: a launch agent property list.
enum LaunchAgent {

    static let label = "com.efoli.Clipstack"

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    static var url: URL {
        directory.appendingPathComponent("\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// The agent runs the executable directly rather than going through `open`:
    /// Clipstack is an agent app with no interface to bring forward, and a
    /// direct path means `launchd` can tell whether it is still running.
    ///
    /// Pure, so the contents can be tested without touching the home directory.
    static func contents(executablePath: String, label: String = label) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            // Not a daemon: if the user quits Clipstack, it stays quit.
            "KeepAlive": false,
        ]
    }

    static func set(_ enabled: Bool, executablePath: String = Bundle.main.executablePath ?? "") {
        do {
            if enabled {
                guard !executablePath.isEmpty else {
                    NSLog("Clipstack: cannot enable launch at login, executable path is unknown")
                    return
                }
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                let data = try PropertyListSerialization.data(
                    fromPropertyList: contents(executablePath: executablePath),
                    format: .xml,
                    options: 0
                )
                try data.write(to: url, options: .atomic)
            } else if isInstalled {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            NSLog("Clipstack: launch agent %@ failed: %@", enabled ? "write" : "remove", "\(error)")
        }
    }
}
