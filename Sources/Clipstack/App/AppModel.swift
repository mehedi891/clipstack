import AppKit
import ClipstackCore
import SwiftUI

/// Owns the app's long-lived objects and the actions the UI triggers.
@MainActor
final class AppModel: ObservableObject {

    let store: ClipboardStore
    let settings: AppSettings
    let monitor: ClipboardMonitor
    let recents = RecentsStore()

    private let persistence: SQLitePersistence?

    /// Surfaced in the UI when history cannot be stored, rather than failing silently.
    @Published private(set) var storageError: String?

    /// Set when a paste fell back to copy-only because Accessibility is not
    /// granted, so the panel can explain why nothing was typed.
    @Published var needsAccessibility = false

    @Published private(set) var accessibilityGranted = AccessibilityPermission.isTrusted

    /// Set when the app is somewhere permissions cannot persist from — a
    /// mounted disk image, or a translocated copy.
    let installLocation = InstallLocation.current()

    /// False when the chosen shortcut is already claimed by another app.
    @Published var hotkeyRegistered = true

    init() {
        // Before anything reads from disk or preferences.
        let migration = LegacyMigration.run()
        if migration.didAnything {
            NSLog(
                "Clipstack: migrated from MacClipboard (directory: %@, settings: %@)",
                migration.movedDirectory ? "yes" : "no",
                migration.migratedDefaultKeys.joined(separator: ", ")
            )
        }

        let persistence: SQLitePersistence?
        var storageError: String?
        do {
            persistence = try SQLitePersistence()
        } catch {
            persistence = nil
            storageError = "\(error)"
            NSLog("Clipstack: %@", "\(error)")
        }

        self.persistence = persistence
        self.storageError = storageError

        let settings = AppSettings()
        self.settings = settings
        self.store = ClipboardStore(capacity: settings.capacity, persistence: persistence)
        self.monitor = ClipboardMonitor(persistence: persistence)

        store.load()

        monitor.onCapture = { [weak self] item in
            self?.store.insert(item)
        }

        if settings.historyEnabled {
            monitor.start()
        }

        // The system owns this setting; the user can revoke it in System
        // Settings without telling us, so trust it over our stored copy.
        settings.launchAtLogin = LaunchAtLogin.isEnabled

        observeAccessibilityChanges()
    }

    /// macOS broadcasts this when the Accessibility list changes, so toggling
    /// the switch takes effect without reopening the panel.
    private func observeAccessibilityChanges() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification arrives marginally before the new state is readable.
            //
            // `self` is re-captured and bound to a local here rather than used
            // as `self?` inside `assumeIsolated`. Swift 5.9 rejects reading the
            // outer closure's weak capture from a nested concurrent one, so the
            // shorter version does not build on older Command Line Tools.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let model = self else { return }
                MainActor.assumeIsolated { model.refreshAccessibilityState() }
            }
        }
    }

    // MARK: - Actions

    func setHistoryEnabled(_ enabled: Bool) {
        settings.historyEnabled = enabled
        if enabled {
            monitor.start()
        } else {
            monitor.stop()
        }
    }

    func setCapacity(_ value: Int) {
        settings.capacity = value
        store.capacity = settings.capacity
    }

    /// Places an entry back on the system pasteboard.
    func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)

        case .richText:
            if let rtf = item.rtf {
                pasteboard.setData(rtf, forType: .rtf)
            }
            // Always include plain text so fields that reject RTF still work.
            pasteboard.setString(item.text ?? "", forType: .string)

        case .image:
            if let image = image(for: item), let png = image.pngRepresentation {
                pasteboard.setData(png, forType: .png)
            }
        }

        // Stops our own write from re-entering the history as a new entry.
        monitor.acknowledgeOwnWrite()
    }

    /// Result of the last permission reset, for the Settings window to show.
    @Published var resetOutcome: AccessibilityPermission.ResetOutcome?

    /// Clears this app's Accessibility records so the permission can be granted
    /// cleanly. See `AccessibilityPermission.reset`.
    func resetAccessibilityPermission() {
        let outcome = AccessibilityPermission.reset()
        resetOutcome = outcome

        guard outcome.succeeded else { return }

        // The permission is gone now, whatever it was before.
        accessibilityGranted = false
        needsAccessibility = false

        // Sending them straight to the list saves hunting for it, and it is
        // where the app has to be re-added by hand anyway.
        AccessibilityPermission.openSettings()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = LaunchAtLogin.set(enabled)
    }

    /// Re-reads permission state; called when the panel or settings open, so a
    /// permission granted in System Settings takes effect without a relaunch.
    func refreshAccessibilityState() {
        accessibilityGranted = AccessibilityPermission.isTrusted
        if accessibilityGranted || installLocation.blocksPermissions {
            // From a disk image the prompt is unanswerable, so the location
            // banner is shown instead of nagging about permissions.
            needsAccessibility = false
        }
    }

    /// Used by the emoji, kaomoji and symbol tabs.
    func copyTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        monitor.acknowledgeOwnWrite()
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard let filename = item.imageFilename, let persistence else { return nil }
        return NSImage(contentsOf: persistence.imageURL(forFilename: filename))
    }
}
