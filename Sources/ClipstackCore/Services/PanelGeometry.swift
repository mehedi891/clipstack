import Foundation

/// Where the floating panel should sit.
///
/// Pure maths, kept out of the view layer so the "never off-screen" rule can be
/// tested. A panel that hangs past a screen edge is unreachable, and on the
/// bottom edge it disappears behind the Dock.
public enum PanelGeometry {

    /// Inset kept between the panel and the screen edges.
    public static let margin: CGFloat = 8

    /// Places the panel just below the pointer, clamped inside `visibleFrame`.
    ///
    /// `visibleFrame` already excludes the menu bar and Dock, so clamping to it
    /// is enough to keep the whole panel reachable.
    public static func origin(
        forMouse mouse: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        var x = mouse.x - panelSize.width / 2
        var y = mouse.y - panelSize.height - margin

        // When the panel is larger than the screen there is no valid position;
        // pinning to the top-left keeps the header and its controls visible.
        let maxX = max(visibleFrame.minX + margin, visibleFrame.maxX - panelSize.width - margin)
        let maxY = max(visibleFrame.minY + margin, visibleFrame.maxY - panelSize.height - margin)

        x = min(max(x, visibleFrame.minX + margin), maxX)
        y = min(max(y, visibleFrame.minY + margin), maxY)

        return CGPoint(x: x, y: y)
    }
}
