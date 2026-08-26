import AppKit
import SwiftUI

/// Design tokens for the panel.
///
/// Follows a "Modern Dark" system: deep navy rather than pure black (which
/// smears on OLED and reads harsh next to macOS vibrancy), a violet→cyan accent
/// gradient, hairline borders, and a dense 4pt spacing rhythm suited to a small
/// floating window.
///
/// Every colour is defined for both appearances. macOS panels are translucent,
/// so the same view sits over whatever is behind it in either theme.
enum Theme {

    // MARK: - Spacing (4pt rhythm, dense)

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
    }

    // MARK: - Colour

    /// Builds an appearance-reactive colour. NSColor re-evaluates the closure
    /// when the system theme changes, so views update without extra state.
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// Tint laid over the window material to give the glass a colour cast.
    static let surfaceTint = adaptive(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55),
        dark: NSColor(srgbRed: 0.059, green: 0.090, blue: 0.165, alpha: 0.62)   // #0F172A
    )

    /// Resting background for a row or cell.
    static let card = adaptive(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.70),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.045)
    )

    /// Row background on hover.
    static let cardHover = adaptive(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.085)
    )

    /// Hairline border. Kept visible in both themes so structure never
    /// disappears in light mode.
    static let border = adaptive(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
    )

    /// Recessed background for the search field.
    static let inputBackground = adaptive(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.05),
        dark: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22)
    )

    // MARK: - Accent

    static let accentStart = Color(red: 0.42, green: 0.36, blue: 0.98)   // violet
    static let accentEnd = Color(red: 0.24, green: 0.72, blue: 0.94)     // cyan

    static let accentGradient = LinearGradient(
        colors: [accentStart, accentEnd],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Faint accent wash behind a selected row.
    static let accentWash = LinearGradient(
        colors: [accentStart.opacity(0.22), accentEnd.opacity(0.14)],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let danger = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let pinned = Color(red: 0.98, green: 0.75, blue: 0.29)

    // MARK: - Motion

    /// Expo-out: fast start, long settle. Used for hover and selection.
    static let quick = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)

    /// Springy, for anything that changes layout.
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.78)

    /// Press feedback scale, per the design system's 0.97 → 1.0 guidance.
    static let pressScale: CGFloat = 0.97
}

// MARK: - Shared modifiers

/// Scales slightly while held, giving every control physical feedback.
/// Layout bounds are unaffected, so nothing around it shifts.
///
/// Also carries the pointing-hand cursor, so every control in the panel gets it
/// from one place rather than each view remembering to ask.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = Theme.pressScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .pointingHandCursor()
    }
}

/// Shows the pointing-hand cursor over a view.
///
/// macOS 15 has a first-class modifier for this. Below that, cursor *rects* are
/// used rather than `NSCursor.push()`/`pop()`: the stack is easy to unbalance
/// when a view disappears while hovered — a row being deleted, a tab switch, the
/// panel closing — which leaves the hand cursor stuck system-wide. AppKit owns
/// the lifetime of a cursor rect, so it cannot leak.
private struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        // `pointerStyle` has to exist in the SDK to compile, not just at run
        // time, and Command Line Tools older than 16 ship the macOS 14 SDK,
        // where it does not. `#available` alone would still fail to build
        // there, so the modifier is compiled out entirely and every version
        // falls back to the cursor rect, which behaves the same.
        #if compiler(>=6.0)
        if #available(macOS 15.0, *) {
            content.pointerStyle(.link)
        } else {
            content.overlay(CursorRect().allowsHitTesting(false))
        }
        #else
        content.overlay(CursorRect().allowsHitTesting(false))
        #endif
    }
}

private struct CursorRect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { View() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class View: NSView {
        /// Never intercept clicks; this view exists only to own a cursor rect.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

extension View {
    /// Hairline stroke that follows a shape's corner radius.
    func hairline(_ radius: CGFloat, color: Color = Theme.border, width: CGFloat = 1) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: width)
        )
    }
}
