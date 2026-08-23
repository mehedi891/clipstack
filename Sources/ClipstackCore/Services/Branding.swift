import AppKit

/// Bundled brand assets.
public enum Branding {

    /// Menu-bar glyph.
    ///
    /// Deliberately an SF Symbol rather than a bespoke drawing. A custom
    /// two-sheet mark was tried first and read as a padlock at 18pt — system
    /// symbols are drawn for that exact size and optical weight, and stay
    /// legible where a scaled-down logo does not.
    ///
    /// `list.clipboard` shows a clipboard carrying lines of text, which is
    /// literally what this app holds. Template mode lets AppKit tint it for
    /// light and dark menu bars and for the highlighted state.
    public static func menuBarIcon() -> NSImage? {
        let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clipstack")
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipstack")

        // Matches the weight of the system items sharing the menu bar.
        let configured = image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        )
        configured?.isTemplate = true
        return configured ?? image
    }
}
