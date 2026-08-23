import AppKit
import Foundation
import Testing
@testable import ClipstackCore

@Suite("Clipboard monitor")
@MainActor
struct ClipboardMonitorTests {

    /// A private pasteboard, so tests never disturb the user's real clipboard.
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("ClipstackTests-\(UUID().uuidString)"))
    }

    @Test("plain text is captured")
    func capturesPlainText() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("hello world", forType: .string)

        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        let item = monitor.readCurrentContents()

        #expect(item?.kind == .text)
        #expect(item?.text == "hello world")
    }

    @Test("rich text is preferred over the plain-text representation")
    func prefersRichText() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setData(Data("{\\rtf1 styled}".utf8), forType: .rtf)
        pasteboard.setString("styled", forType: .string)

        let item = ClipboardMonitor(pasteboard: pasteboard).readCurrentContents()

        #expect(item?.kind == .richText)
        #expect(item?.text == "styled")
        #expect(item?.rtf != nil)
    }

    @Test("entries marked concealed by password managers are ignored")
    func ignoresConcealed() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("hunter2", forType: .string)
        pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))

        #expect(ClipboardMonitor(pasteboard: pasteboard).readCurrentContents() == nil)
    }

    @Test("transient entries are ignored")
    func ignoresTransient() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("temporary", forType: .string)
        pasteboard.setData(Data(), forType: .init("org.nspasteboard.TransientType"))

        #expect(ClipboardMonitor(pasteboard: pasteboard).readCurrentContents() == nil)
    }

    @Test("whitespace-only copies are not recorded")
    func ignoresWhitespace() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("   \n\t ", forType: .string)

        #expect(ClipboardMonitor(pasteboard: pasteboard).readCurrentContents() == nil)
    }

    @Test("an empty pasteboard yields nothing")
    func ignoresEmpty() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()

        #expect(ClipboardMonitor(pasteboard: pasteboard).readCurrentContents() == nil)
    }

    /// Built from an explicit bitmap rep rather than `lockFocus`, which backs
    /// the image at the display's scale and would give 8x8 pixels on Retina.
    private func makePNG(width: Int, height: Int) throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test("images are captured and their bytes written through persistence")
    func capturesImage() throws {
        let png = try makePNG(width: 4, height: 4)

        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)

        let fake = FakePersistence()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, persistence: fake)
        let item = monitor.readCurrentContents()

        #expect(item?.kind == .image)
        #expect(item?.imageFilename == "fake.png")
        #expect(item?.preview == "Image 4×4")
    }

    @Test("images are skipped when there is nowhere to store the bytes")
    func skipsImageWithoutPersistence() throws {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.setData(try makePNG(width: 2, height: 2), forType: .png)

        // No persistence: an image row would reference a file that never exists.
        #expect(ClipboardMonitor(pasteboard: pasteboard).readCurrentContents() == nil)
    }

    @Test("our own writes are not re-captured")
    func ignoresOwnWrites() {
        let pasteboard = makePasteboard()
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        monitor.start()
        defer { monitor.stop() }

        var captured: [ClipboardItem] = []
        monitor.onCapture = { captured.append($0) }

        // Simulate PasteService putting an item back on the pasteboard.
        pasteboard.clearContents()
        pasteboard.setString("pasted back", forType: .string)
        monitor.acknowledgeOwnWrite()

        monitor.pollForTesting()

        #expect(captured.isEmpty)
    }

    @Test("a genuine external change is captured")
    func capturesExternalChange() {
        let pasteboard = makePasteboard()
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        monitor.start()
        defer { monitor.stop() }

        var captured: [ClipboardItem] = []
        monitor.onCapture = { captured.append($0) }

        pasteboard.clearContents()
        pasteboard.setString("copied elsewhere", forType: .string)

        monitor.pollForTesting()

        #expect(captured.map(\.text) == ["copied elsewhere"])
    }
}
