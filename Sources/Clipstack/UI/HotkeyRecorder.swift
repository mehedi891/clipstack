import AppKit
import Carbon.HIToolbox
import ClipstackCore
import SwiftUI

/// Click, then press a shortcut to rebind it.
///
/// Recording uses a plain first-responder NSView rather than an event monitor,
/// so the keystroke is captured only while this control is focused and never
/// leaks to the rest of the app.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var combo: GlobalHotkey.Combo

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = { combo = $0 }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.combo = combo
    }

    final class RecorderView: NSView {
        var onCapture: ((GlobalHotkey.Combo) -> Void)?

        var combo: GlobalHotkey.Combo = .commandShiftV {
            didSet { needsDisplay = true }
        }

        private var isRecording = false {
            didSet { needsDisplay = true }
        }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 22) }

        override func mouseDown(with event: NSEvent) {
            isRecording = true
            window?.makeFirstResponder(self)
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }

            // Esc cancels without changing anything.
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return
            }

            guard let captured = GlobalHotkey.Combo(event: event) else {
                // No modifier held: a bare key would be swallowed system-wide.
                NSSound.beep()
                return
            }

            combo = captured
            onCapture?(captured)
            stopRecording()
        }

        /// Swallow the shortcut so it does not also trigger a menu item.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording else { return false }
            keyDown(with: event)
            return true
        }

        private func stopRecording() {
            isRecording = false
            window?.makeFirstResponder(nil)
        }

        override func draw(_ dirtyRect: NSRect) {
            let rounded = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)

            (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
            rounded.fill()
            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            rounded.lineWidth = isRecording ? 1.5 : 1
            rounded.stroke()

            let text = isRecording ? "Press keys…" : combo.displayString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                withAttributes: attributes
            )
        }
    }
}
