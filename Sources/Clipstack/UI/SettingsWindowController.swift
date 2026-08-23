import AppKit
import SwiftUI

/// Hosts the settings form in a standard window.
///
/// A menu-bar agent has no Dock icon, so the app is switched to `.regular`
/// while settings are open — otherwise the window cannot be focused or found
/// in the app switcher.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func show() {
        if let window {
            activate(window)
            return
        }

        let view = SettingsView()
            .environmentObject(model)
            .environmentObject(model.store)
            .environmentObject(model.settings)

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Clipstack Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window
        activate(window)
    }

    private func activate(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu-bar-only app.
        NSApp.setActivationPolicy(.accessory)
    }
}
