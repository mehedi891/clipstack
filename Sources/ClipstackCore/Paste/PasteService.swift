import AppKit
import Carbon.HIToolbox
import Foundation

/// Returns focus to the app the user was working in and synthesizes Cmd+V,
/// reproducing the Windows behaviour where picking an entry types it straight
/// into the focused field.
@MainActor
public enum PasteService {

    public enum Outcome: Equatable {
        /// Keystroke posted; the content should now be in the target field.
        case pasted
        /// Content is on the clipboard, but Accessibility permission is missing
        /// so the user must press Cmd+V themselves.
        case needsAccessibilityPermission
        /// Content is on the clipboard; there was no app to paste into.
        case copiedOnly
    }

    /// How long to wait for the target app to come back to the front before
    /// giving up and posting anyway.
    private static let activationTimeout: TimeInterval = 0.5
    private static let pollInterval: TimeInterval = 0.02

    /// Assumes the caller has already put the content on the pasteboard.
    ///
    /// - Parameter target: the app that was frontmost before the panel opened.
    @discardableResult
    public static func paste(into target: NSRunningApplication?) async -> Outcome {
        guard let target, !target.isTerminated else { return .copiedOnly }

        guard isTrusted else {
            // Shows the standard macOS permission dialog the first time, which
            // is far clearer than our banner appearing on its own.
            AccessibilityPermission.requestAccess()
            return .needsAccessibilityPermission
        }

        target.activate()
        await waitForActivation(of: target)
        postCommandV()
        return .pasted
    }

    /// Seam for tests; production reads the real permission state.
    static var isTrusted: Bool { AccessibilityPermission.isTrusted }

    /// Polls rather than sleeping a fixed interval: activation is usually much
    /// faster than a worst-case delay, and occasionally slower.
    private static func waitForActivation(of app: NSRunningApplication) async {
        let deadline = Date().addingTimeInterval(activationTimeout)

        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                // A beat more, so the app has focused its text field.
                try? await Task.sleep(nanoseconds: 30_000_000)
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    private static func postCommandV() {
        // .combinedSessionState so the events reach the frontmost app.
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return }

        // Set explicitly rather than OR-ing, so a modifier the user is still
        // physically holding (Shift from the hotkey) cannot turn this into
        // paste-and-match-style.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
