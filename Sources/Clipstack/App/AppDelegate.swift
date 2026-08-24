import AppKit
import Combine
import ClipstackCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var hotkey: GlobalHotkey?
    private var cancellables = Set<AnyCancellable>()

    private let model = AppModel()
    private lazy var panelController = PanelController(model: model)
    private lazy var settingsController = SettingsWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpHotkey()
        logStartupState()

        // Opens the settings window at launch, so screenshots can be captured
        // without driving the menu bar.
        if ProcessInfo.processInfo.environment["CLIPSTACK_DEBUG_SETTINGS"] != nil {
            settingsController.show()
        }

        // Diagnostic: open the panel and report its real geometry.
        if ProcessInfo.processInfo.environment["CLIPSTACK_DEBUG_PANEL"] != nil {
            panelController.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                MainActor.assumeIsolated { self.panelController.logGeometry() }
            }
        }
    }

    /// Bundle.module resolves differently inside an assembled .app than under
    /// `swift test`, so the catalogue counts are worth recording once.
    private func logStartupState() {
        NSLog(
            "Clipstack ready: %d emoji, %d kaomoji, %d symbols; hotkey=%@, accessibility=%@",
            Catalogues.emoji.reduce(0) { $0 + $1.emoji.count },
            Catalogues.kaomoji.reduce(0) { $0 + $1.symbols.count },
            Catalogues.symbols.reduce(0) { $0 + $1.symbols.count },
            hotkey == nil ? "FAILED" : "ok",
            AccessibilityPermission.isTrusted ? "granted" : "not granted"
        )
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        item.button?.image = Branding.menuBarIcon()
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    private func setUpHotkey() {
        registerHotkey(model.settings.hotkey)

        // Rebind as soon as the user records a new shortcut.
        model.settings.$hotkey
            .dropFirst()
            .sink { [weak self] combo in self?.registerHotkey(combo) }
            .store(in: &cancellables)
    }

    private func registerHotkey(_ combo: GlobalHotkey.Combo) {
        // Released before re-registering, or the old binding stays live.
        hotkey = nil

        hotkey = GlobalHotkey(combo: combo) { [weak self] in
            self?.panelController.toggle()
        }

        model.hotkeyRegistered = (hotkey != nil)
        if hotkey == nil {
            NSLog("Clipstack: could not register %@; another app owns it.", combo.displayString)
        }
    }

    // Left click opens the panel; right click opens the menu.
    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            panelController.toggle()
        }
    }

    private func showMenu() {
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()
        menu.addItem(makeItem("Open Clipboard", #selector(openPanel), key: "v"))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Clipstack",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        // popUp rather than assigning statusItem.menu, which would permanently
        // replace the left-click action.
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    private func makeItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openPanel() {
        panelController.show()
    }

    @objc private func openSettings() {
        settingsController.show()
    }
}
