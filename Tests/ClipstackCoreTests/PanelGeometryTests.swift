import Foundation
import Testing
@testable import ClipstackCore

@Suite("Panel placement")
struct PanelGeometryTests {

    /// A 1440x900 display with the menu bar and Dock excluded.
    private let screen = CGRect(x: 0, y: 48, width: 1440, height: 822)
    private let panel = CGSize(width: 360, height: 500)

    private func place(mouseAt point: CGPoint) -> CGRect {
        let origin = PanelGeometry.origin(forMouse: point, panelSize: panel, visibleFrame: screen)
        return CGRect(origin: origin, size: panel)
    }

    @Test("the panel opens centred under the pointer when there is room")
    func centredUnderPointer() {
        let frame = place(mouseAt: CGPoint(x: 700, y: 700))

        #expect(frame.midX == 700)
        #expect(frame.maxY == 700 - PanelGeometry.margin)
    }

    @Test("the panel never hangs off any screen edge", arguments: [
        CGPoint(x: 0, y: 0),            // bottom-left corner
        CGPoint(x: 1440, y: 900),       // top-right corner
        CGPoint(x: 1440, y: 0),         // bottom-right corner
        CGPoint(x: 0, y: 900),          // top-left corner
        CGPoint(x: 720, y: 60),         // near the Dock
        CGPoint(x: 5, y: 500),          // hard against the left edge
        CGPoint(x: 1435, y: 500),       // hard against the right edge
    ])
    func staysOnScreen(mouse: CGPoint) {
        let frame = place(mouseAt: mouse)

        #expect(frame.minX >= screen.minX, "off the left edge")
        #expect(frame.maxX <= screen.maxX, "off the right edge")
        #expect(frame.minY >= screen.minY, "behind the Dock")
        #expect(frame.maxY <= screen.maxY, "under the menu bar")
    }

    @Test("a margin is kept from the edges")
    func keepsMargin() {
        let frame = place(mouseAt: CGPoint(x: 0, y: 0))

        #expect(frame.minX == screen.minX + PanelGeometry.margin)
        #expect(frame.minY == screen.minY + PanelGeometry.margin)
    }

    @Test("a panel taller than the screen still shows its header")
    func oversizedPanelPinsToTopLeft() {
        // The regression that made the panel 1384pt tall on an 822pt screen.
        let oversized = CGSize(width: 360, height: 1384)
        let origin = PanelGeometry.origin(
            forMouse: CGPoint(x: 700, y: 400),
            panelSize: oversized,
            visibleFrame: screen
        )

        // It cannot fit, but the top edge must not sit above the visible area,
        // or the header and tab strip would be unreachable.
        #expect(origin.y == screen.minY + PanelGeometry.margin)
        #expect(origin.x >= screen.minX)
    }

    @Test("placement works on a secondary display with a non-zero origin")
    func secondaryDisplay() {
        let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let origin = PanelGeometry.origin(
            forMouse: CGPoint(x: 1450, y: 20),
            panelSize: panel,
            visibleFrame: external
        )

        #expect(origin.x >= external.minX + PanelGeometry.margin)
        #expect(origin.y >= external.minY + PanelGeometry.margin)
    }
}
