import Foundation
import Testing
@testable import ClipstackCore

@Suite("SQLite persistence")
struct PersistenceTests {

    /// Each test gets a throwaway directory so runs cannot interfere.
    private func makeStore() throws -> (SQLitePersistence, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClipstackTests-\(UUID().uuidString)")
        return (try SQLitePersistence(directory: dir), dir)
    }

    @Test("items survive a save and reload")
    func roundTrip() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = [
            ClipboardItem.text("hello", createdAt: Date(timeIntervalSince1970: 1000)),
            ClipboardItem.richText(
                rtf: Data("{\\rtf1 styled}".utf8),
                plainText: "styled",
                createdAt: Date(timeIntervalSince1970: 2000)
            ),
            ClipboardItem.image(
                filename: "a.png",
                pngData: Data([0xDE, 0xAD]),
                pixelSize: "4×4",
                createdAt: Date(timeIntervalSince1970: 3000)
            ),
        ]

        try store.saveItems(original)
        let reloaded = try store.loadItems()

        #expect(reloaded.count == 3)
        // Newest first, per the ORDER BY.
        #expect(reloaded.map(\.preview) == ["Image 4×4", "styled", "hello"])
        #expect(reloaded.map(\.kind) == [.image, .richText, .text])
    }

    @Test("every field is preserved exactly")
    func fieldsPreserved() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var original = ClipboardItem.richText(
            rtf: Data([0x01, 0x02, 0x03]),
            plainText: "body",
            createdAt: Date(timeIntervalSince1970: 1_234_567),
            sourceBundleID: "com.apple.TextEdit"
        )
        original.pinned = true

        try store.saveItems([original])
        let loaded = try #require(try store.loadItems().first)

        #expect(loaded.id == original.id)
        #expect(loaded.kind == original.kind)
        #expect(loaded.text == "body")
        #expect(loaded.rtf == Data([0x01, 0x02, 0x03]))
        #expect(loaded.pinned)
        #expect(loaded.sourceBundleID == "com.apple.TextEdit")
        #expect(loaded.contentHash == original.contentHash)
        #expect(abs(loaded.createdAt.timeIntervalSince(original.createdAt)) < 0.001)
    }

    @Test("saving replaces the previous contents rather than appending")
    func savesReplace() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.saveItems([.text("first")])
        try store.saveItems([.text("second")])

        let loaded = try store.loadItems()
        #expect(loaded.map(\.preview) == ["second"])
    }

    @Test("a reopened database still holds the history")
    func survivesReopen() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClipstackTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            let store = try SQLitePersistence(directory: dir)
            try store.saveItems([.text("persisted")])
        }

        let reopened = try SQLitePersistence(directory: dir)
        #expect(try reopened.loadItems().map(\.preview) == ["persisted"])
    }

    @Test("images are written to disk and removed on delete")
    func imageLifecycle() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let filename = try store.saveImage(Data([0x89, 0x50, 0x4E, 0x47]))
        let url = store.imageURL(forFilename: filename)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let item = ClipboardItem.image(
            filename: filename,
            pngData: Data([0x89, 0x50, 0x4E, 0x47]),
            pixelSize: "1×1"
        )
        store.deleteImage(for: item)

        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite("Clearing writes through to disk")
@MainActor
struct ClearPersistenceTests {

    private func makeDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClipstackTests-\(UUID().uuidString)")
    }

    @Test("cleared pinned items do not come back after a relaunch")
    func deleteAllPinnedSurvivesRelaunch() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let store = ClipboardStore(capacity: 20, persistence: try SQLitePersistence(directory: directory))
            store.insert(.text("keep me loose", createdAt: Date(timeIntervalSince1970: 1)))
            store.insert(.text("pinned one", createdAt: Date(timeIntervalSince1970: 2)))
            store.togglePin(store.items[0].id)

            store.deleteAllPinned()
            #expect(store.pinnedItems.isEmpty)
        }

        // Reopen from scratch, as a relaunch would.
        let reopened = ClipboardStore(capacity: 20, persistence: try SQLitePersistence(directory: directory))
        reopened.load()

        #expect(reopened.pinnedItems.isEmpty)
        #expect(reopened.items.map(\.preview) == ["keep me loose"])
    }

    @Test("clearing history keeps pinned items across a relaunch")
    func clearAllSurvivesRelaunch() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let store = ClipboardStore(capacity: 20, persistence: try SQLitePersistence(directory: directory))
            store.insert(.text("transient", createdAt: Date(timeIntervalSince1970: 1)))
            store.insert(.text("pinned", createdAt: Date(timeIntervalSince1970: 2)))
            store.togglePin(store.items[0].id)

            store.clearAll()
        }

        let reopened = ClipboardStore(capacity: 20, persistence: try SQLitePersistence(directory: directory))
        reopened.load()

        #expect(reopened.items.map(\.preview) == ["pinned"])
    }
}
