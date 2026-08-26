import AppKit
import SwiftUI

// Shims for the two SwiftUI APIs the panel relied on that do not exist before
// macOS 14. Both keep the call sites in the tab views readable, rather than
// spreading `if #available` through the view bodies.

extension View {

    /// `onChange(of:_:)`, available on macOS 12.
    ///
    /// The two-parameter closure arrived in macOS 14. The single-parameter form
    /// below is deprecated there but is the only one older systems have.
    @ViewBuilder
    func onValueChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }

    /// Calls `handler` for the arrow keys, and swallows the ones it handles.
    ///
    /// Replaces `onKeyPress`, which is macOS 14 only. A local event monitor is
    /// the AppKit equivalent and works everywhere, with one difference worth
    /// knowing: monitors are installed per application, not per view, so this
    /// one ignores any event that did not come from its own window. Without
    /// that check, an open settings window would lose its arrow keys to the
    /// panel.
    func onArrowKeys(_ handler: @escaping (ArrowKey) -> Bool) -> some View {
        background(ArrowKeyMonitor(handler: handler))
    }
}

enum ArrowKey {
    case up
    case down

    /// AppKit virtual key codes; `keyCode` avoids depending on the key's
    /// character, which arrow keys do not really have.
    init?(_ event: NSEvent) {
        switch event.keyCode {
        case 126: self = .up
        case 125: self = .down
        default: return nil
        }
    }
}

private struct ArrowKeyMonitor: NSViewRepresentable {
    let handler: (ArrowKey) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.handler = handler
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var handler: ((ArrowKey) -> Bool)?
        private weak var view: NSView?
        private var monitor: Any?

        func attach(to view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard
                    let self,
                    let window = self.view?.window,
                    event.window === window,
                    let key = ArrowKey(event),
                    self.handler?(key) == true
                else { return event }

                return nil   // handled: do not pass it on
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit { detach() }
    }
}

/// `LabeledContent`, available on macOS 12.
///
/// macOS 13 and newer get the real thing, so the settings window keeps its
/// system styling; below that a plain row does the same job by hand.
struct LabeledRow<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            LabeledContent(title) { content }
        } else {
            HStack(spacing: 12) {
                Text(title)
                Spacer(minLength: 12)
                content
            }
        }
    }
}

extension View {
    /// `.formStyle(.grouped)` where it exists. macOS 12's only form style is
    /// the one it already uses.
    @ViewBuilder
    func groupedFormStyle() -> some View {
        if #available(macOS 13.0, *) {
            formStyle(.grouped)
        } else {
            self
        }
    }
}
