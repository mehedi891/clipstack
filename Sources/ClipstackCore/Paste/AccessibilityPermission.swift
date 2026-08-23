import AppKit
import ApplicationServices

/// Accessibility ("control your computer") permission, which macOS requires
/// before one app may post synthetic keystrokes into another.
public enum AccessibilityPermission {

    /// Current state. Cheap enough to call on every paste.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Checks, and shows the system prompt when not yet granted.
    ///
    /// macOS only shows the prompt once per app signature; afterwards the user
    /// must go to System Settings, which `openSettings()` links to.
    @discardableResult
    public static func requestAccess() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Reset

    public enum ResetOutcome: Equatable {
        /// Records were cleared. More than one means macOS was holding
        /// conflicting entries, which is the usual cause of a permission that
        /// appears granted but does not work.
        case cleared(records: Int)
        /// Nothing was registered, so there was nothing to clear.
        case nothingToClear
        case failed(String)

        public var succeeded: Bool {
            if case .failed = self { return false }
            return true
        }
    }

    /// Clears this app's Accessibility records from the permission database.
    ///
    /// Exists because macOS can end up holding two records for one app — after
    /// a move, a rename, or a rebuild that changed the signature. System
    /// Settings then shows one entry while the system matches against the
    /// other, so the switch looks on and nothing works. Clearing both and
    /// granting once more is the only fix, and doing it by hand means finding
    /// an obscure Terminal command.
    ///
    /// Runs `tccutil`, which acts on the current user's database and needs no
    /// administrator rights.
    public static func reset(bundleID: String? = Bundle.main.bundleIdentifier) -> ResetOutcome {
        guard let bundleID, !bundleID.isEmpty else {
            return .failed("The app has no bundle identifier.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return .failed("Could not run tccutil: \(error.localizedDescription)")
        }

        // Read before waiting: tccutil's output is tiny, but draining the pipe
        // first avoids deadlocking if that ever changes.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return parseReset(
            output: String(decoding: data, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    /// Split from `reset` so the outcome rules can be unit tested without
    /// touching the real permission database.
    static func parseReset(output: String, exitCode: Int32) -> ResetOutcome {
        guard exitCode == 0 else {
            // macOS has no record of the app at all, which is not an error —
            // there is simply nothing to clear. Reporting it as a failure would
            // alarm someone whose permission was already clean.
            if output.contains("No such bundle identifier") {
                return .nothingToClear
            }

            let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(message.isEmpty ? "tccutil failed with code \(exitCode)." : message)
        }

        let records = output
            .split(separator: "\n")
            .filter { $0.contains("Successfully reset") }
            .count

        return records == 0 ? .nothingToClear : .cleared(records: records)
    }
}
