import AppKit
import ClipstackCore
import SwiftUI

/// A floating panel that shows above other apps without deactivating them.
///
/// `.nonactivatingPanel` keeps the app underneath visually frontmost, while
/// `canBecomeKey` is still true so the search field can accept typing.
final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc closes the panel.
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {

    // Sized for five tabs and a comfortable list length.
    static let size = NSSize(width: 360, height: 500)

    private let model: AppModel
    private var panel: ClipboardPanel?

    /// The app that was frontmost when the panel opened. Auto-paste (M3)
    /// restores focus here before synthesizing Cmd+V.
    private(set) var previousApp: NSRunningApplication?

    var isVisible: Bool { panel?.isVisible ?? false }

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    private func select(_ item: ClipboardItem) {
        deliver { self.model.copyToPasteboard(item) }
    }

    private func insert(_ text: String) {
        deliver { self.model.copyTextToPasteboard(text) }
    }

    /// Puts content on the clipboard and types it into the app the user came
    /// from. Falls back to copy-only when Accessibility is not granted.
    private func deliver(_ writeToPasteboard: () -> Void) {
        // Read before hiding: dismissal changes what is frontmost.
        let target = previousApp

        writeToPasteboard()
        hide()

        Task { @MainActor in
            let outcome = await PasteService.paste(into: target)
            model.needsAccessibility = (outcome == .needsAccessibilityPermission)
        }
    }

    func show() {
        // Captured before the panel appears, while the other app still owns focus.
        previousApp = NSWorkspace.shared.frontmostApplication
        model.refreshAccessibilityState()

        let panel = existingOrNewPanel()
        panel.setFrameOrigin(originNearMouse(for: panel))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func logGeometry() {
        guard let panel else { return NSLog("Clipstack: no panel") }
        NSLog(
            "PANEL frame=%@ content=%@ expected=%@ hosting=%@",
            NSStringFromRect(panel.frame),
            NSStringFromRect(panel.contentView?.frame ?? .zero),
            NSStringFromSize(Self.size),
            NSStringFromSize(panel.contentView?.fittingSize ?? .zero)
        )
        NSLog("SCREEN visible=%@", NSStringFromRect(NSScreen.main?.visibleFrame ?? .zero))
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func existingOrNewPanel() -> ClipboardPanel {
        if let panel { return panel }

        let panel = ClipboardPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.delegate = self

        let root = RootView(
            onSelectItem: { [weak self] item in self?.select(item) },
            onInsertText: { [weak self] text in self?.insert(text) }
        )
            .environmentObject(model)
            .environmentObject(model.store)
            .environmentObject(model.settings)
            .environmentObject(model.recents)

        // Without this the hosting view pushes SwiftUI's ideal size onto the
        // window: a tab whose content prefers to be tall (an empty state with a
        // long message, say) would stretch the panel past the screen edges.
        // The panel owns its size; the content adapts to it.
        //
        // `sizingOptions` says exactly that, but only on macOS 13 and newer, so
        // FixedSizeHostingView refuses to report an intrinsic size at all —
        // which is the same instruction in the language every version speaks.
        let hosting = FixedSizeHostingView(rootView: root)
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(origin: .zero, size: Self.size)

        panel.contentView = hosting
        panel.setContentSize(Self.size)
        // Belt and braces: nothing may resize the panel, in either direction.
        panel.contentMinSize = Self.size
        panel.contentMaxSize = Self.size

        self.panel = panel
        return panel
    }

    /// Place the panel near the pointer, clamped inside the visible screen area.
    private func originNearMouse(for panel: NSPanel) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return mouse }

        return PanelGeometry.origin(
            forMouse: mouse,
            panelSize: panel.frame.size,
            visibleFrame: visible
        )
    }

    // Clicking away dismisses, matching the Windows panel.
    func windowDidResignKey(_ notification: Notification) {
        // A sheet takes key focus from its parent. Hiding here would dismiss
        // the panel out from under its own modal, leaving an invisible dialog
        // holding the app — so leave the panel up while one is attached.
        guard panel?.attachedSheet == nil else { return }
        hide()
    }
}

/// An `NSHostingView` that never asks the window for a particular size.
///
/// SwiftUI's ideal size is advice about content; the panel's size is a product
/// decision. Reporting no intrinsic metric keeps the two from arguing.
private final class FixedSizeHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
