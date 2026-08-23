import Foundation
import Testing
@testable import ClipstackCore

/// In-memory stand-in so the history rules can be tested without touching disk.
final class FakePersistence: PersistenceProtocol {
    var stored: [ClipboardItem] = []
    var deletedImages: [String] = []

    func loadItems() throws -> [ClipboardItem] { stored }
    func saveItems(_ items: [ClipboardItem]) throws { stored = items }
    func saveImage(_ pngData: Data) throws -> String { "fake.png" }
    func imageURL(forFilename filename: String) -> URL { URL(fileURLWithPath: "/tmp/\(filename)") }

    func deleteImage(for item: ClipboardItem) {
        if let name = item.imageFilename { deletedImages.append(name) }
    }
}

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

/// Builds a text item at a deterministic time offset.
private func item(_ text: String, at offset: TimeInterval) -> ClipboardItem {
    .text(text, createdAt: epoch.addingTimeInterval(offset))
}

@Suite("Clipboard history")
@MainActor
struct ClipboardStoreTests {

    @Test("newest entry is listed first")
    func ordering() {
        let store = ClipboardStore(capacity: 10)
        store.insert(item("first", at: 0))
        store.insert(item("second", at: 1))
        store.insert(item("third", at: 2))

        #expect(store.items.map(\.preview) == ["third", "second", "first"])
    }

    @Test("re-copying existing content promotes it instead of duplicating")
    func duplicatesArePromoted() {
        let store = ClipboardStore(capacity: 10)
        store.insert(item("alpha", at: 0))
        store.insert(item("beta", at: 1))

        let wasNew = store.insert(item("alpha", at: 2))

        #expect(wasNew == false)
        #expect(store.items.count == 2)
        #expect(store.items.map(\.preview) == ["alpha", "beta"])
    }

    @Test("styling changes do not create a second entry for the same words")
    func richTextDedupesOnVisibleText() {
        let store = ClipboardStore(capacity: 10)
        store.insert(.richText(rtf: Data("{\\rtf1 bold}".utf8), plainText: "hello", createdAt: epoch))
        store.insert(.richText(rtf: Data("{\\rtf1 italic}".utf8), plainText: "hello", createdAt: epoch.addingTimeInterval(1)))

        #expect(store.items.count == 1)
    }

    @Test("entries beyond capacity are dropped oldest first")
    func capacityEviction() {
        let store = ClipboardStore(capacity: 3)
        for i in 0..<5 {
            store.insert(item("item\(i)", at: TimeInterval(i)))
        }

        #expect(store.items.count == 3)
        #expect(store.items.map(\.preview) == ["item4", "item3", "item2"])
    }

    @Test("pinned entries survive eviction and are not counted against capacity")
    func pinnedSurviveEviction() {
        let store = ClipboardStore(capacity: 2)
        store.insert(item("keep me", at: 0))
        store.togglePin(store.items[0].id)

        for i in 1...5 {
            store.insert(item("filler\(i)", at: TimeInterval(i)))
        }

        #expect(store.items.contains { $0.preview == "keep me" })
        #expect(store.items.filter { !$0.pinned }.count == 2)
        #expect(store.items.count == 3)
    }

    @Test("unpinning re-applies the capacity limit")
    func unpinningReappliesCapacity() {
        let store = ClipboardStore(capacity: 2)
        store.insert(item("old", at: 0))
        store.togglePin(store.items[0].id)
        store.insert(item("a", at: 1))
        store.insert(item("b", at: 2))
        #expect(store.items.count == 3)

        let pinnedID = store.items.first { $0.pinned }!.id
        store.togglePin(pinnedID)

        #expect(store.items.count == 2)
        #expect(!store.items.contains { $0.preview == "old" })
    }

    @Test("clear all keeps pinned entries")
    func clearAllKeepsPinned() {
        let store = ClipboardStore(capacity: 10)
        store.insert(item("pinned", at: 0))
        store.togglePin(store.items[0].id)
        store.insert(item("transient", at: 1))

        store.clearAll()

        #expect(store.items.map(\.preview) == ["pinned"])
    }

    @Test("clearing without keepPinned empties the history")
    func clearAllCanRemoveEverything() {
        let store = ClipboardStore(capacity: 10)
        store.insert(item("pinned", at: 0))
        store.togglePin(store.items[0].id)
        store.insert(item("transient", at: 1))

        store.clearAll(keepPinned: false)

        #expect(store.items.isEmpty)
    }

    @Test("deleting removes only the requested entry")
    func deleteRemovesOne() {
        let store = ClipboardStore(capacity: 10)
        store.insert(item("a", at: 0))
        store.insert(item("b", at: 1))

        store.delete(store.items[0].id)

        #expect(store.items.map(\.preview) == ["a"])
    }

    @Test("search ignores case and diacritics")
    func search() {
        let store = ClipboardStore(capacity: 10)
        store.insert(item("Café receipt", at: 0))
        store.insert(item("unrelated", at: 1))

        #expect(store.filtered(by: "cafe").map(\.preview) == ["Café receipt"])
        #expect(store.filtered(by: "  ").count == 2)
        #expect(store.filtered(by: "nothing here").isEmpty)
    }

    @Test("multi-line copies preview as a single collapsed line")
    func previewCollapsesWhitespace() {
        let entry = ClipboardItem.text("line one\n\n   line two\t")
        #expect(entry.preview == "line one line two")
    }

    // MARK: - Persistence seam

    @Test("changes are written through to persistence")
    func writesThrough() {
        let fake = FakePersistence()
        let store = ClipboardStore(capacity: 10, persistence: fake)

        store.insert(item("saved", at: 0))

        #expect(fake.stored.map(\.preview) == ["saved"])
    }

    @Test("load restores newest-first order regardless of stored order")
    func loadSorts() {
        let fake = FakePersistence()
        fake.stored = [item("old", at: 0), item("new", at: 5), item("mid", at: 2)]

        let store = ClipboardStore(capacity: 10, persistence: fake)
        store.load()

        #expect(store.items.map(\.preview) == ["new", "mid", "old"])
    }

    @Test("evicting an image entry deletes its file")
    func evictionDeletesImageFile() {
        let fake = FakePersistence()
        let store = ClipboardStore(capacity: 1, persistence: fake)

        store.insert(.image(filename: "shot.png", pngData: Data([1, 2, 3]), pixelSize: "10×10", createdAt: epoch))
        store.insert(item("pushes the image out", at: 1))

        #expect(fake.deletedImages == ["shot.png"])
    }
}

@Suite("Pinned tab")
@MainActor
struct PinnedItemsTests {

    /// Builds a store with two pinned entries among four.
    private func makeStore(persistence: FakePersistence? = nil) -> ClipboardStore {
        let store = ClipboardStore(capacity: 50, persistence: persistence)
        for (index, text) in ["alpha", "beta", "gamma", "delta"].enumerated() {
            store.insert(item(text, at: TimeInterval(index)))
        }
        // Pin "beta" and "delta".
        for entry in store.items where entry.preview == "beta" || entry.preview == "delta" {
            store.togglePin(entry.id)
        }
        return store
    }

    @Test("pinnedItems returns only pinned entries, newest first")
    func listsOnlyPinned() {
        let store = makeStore()
        #expect(store.pinnedItems.map(\.preview) == ["delta", "beta"])
    }

    @Test("pinnedItems is empty when nothing is pinned")
    func emptyWhenNonePinned() {
        let store = ClipboardStore(capacity: 10)
        store.insert(item("unpinned", at: 0))
        #expect(store.pinnedItems.isEmpty)
    }

    @Test("searching pinned entries excludes unpinned matches")
    func searchStaysWithinPinned() {
        let store = ClipboardStore(capacity: 10)
        store.insert(item("shared word pinned", at: 0))
        store.togglePin(store.items[0].id)
        store.insert(item("shared word loose", at: 1))

        let results = store.filteredPinned(by: "shared word")
        #expect(results.map(\.preview) == ["shared word pinned"])
    }

    @Test("deleteAllPinned removes pinned entries and keeps the rest")
    func deleteAllPinnedKeepsOthers() {
        let store = makeStore()
        store.deleteAllPinned()

        #expect(store.pinnedItems.isEmpty)
        #expect(store.items.map(\.preview) == ["gamma", "alpha"])
    }

    @Test("deleteAllPinned on an empty selection changes nothing")
    func deleteAllPinnedNoOp() {
        let store = ClipboardStore(capacity: 10)
        store.insert(item("loose", at: 0))

        store.deleteAllPinned()

        #expect(store.items.map(\.preview) == ["loose"])
    }

    @Test("deleting pinned entries removes their image files")
    func deleteAllPinnedCleansUpImages() {
        let fake = FakePersistence()
        let store = ClipboardStore(capacity: 10, persistence: fake)

        store.insert(.image(filename: "pinned.png", pngData: Data([1]), pixelSize: "2×2", createdAt: epoch))
        store.togglePin(store.items[0].id)
        store.deleteAllPinned()

        #expect(fake.deletedImages == ["pinned.png"])
        #expect(fake.stored.isEmpty)
    }

    @Test("unpinning moves an entry out of the pinned list but keeps it in history")
    func unpinningKeepsContent() {
        let store = makeStore()
        let target = store.pinnedItems.first!

        store.togglePin(target.id)

        #expect(store.pinnedItems.map(\.preview) == ["beta"])
        #expect(store.items.contains { $0.preview == "delta" })
    }

    @Test("clearAll leaves the pinned tab untouched")
    func clearAllPreservesPinnedTab() {
        let store = makeStore()
        store.clearAll()
        #expect(store.pinnedItems.map(\.preview) == ["delta", "beta"])
    }
}
