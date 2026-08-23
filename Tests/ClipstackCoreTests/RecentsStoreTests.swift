import Foundation
import Testing
@testable import ClipstackCore

@Suite("Recently used glyphs")
@MainActor
struct RecentsStoreTests {

    /// An isolated defaults domain per test, so nothing leaks between runs or
    /// touches the real preferences.
    private func makeStore() -> (RecentsStore, UserDefaults, String) {
        let name = "ClipstackTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (RecentsStore(defaults: defaults), defaults, name)
    }

    @Test("most recent entry comes first")
    func ordering() {
        let (store, _, name) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        store.record("😀", kind: .emoji)
        store.record("🚀", kind: .emoji)

        #expect(store.recents(for: .emoji) == ["🚀", "😀"])
    }

    @Test("re-using an entry moves it to the front instead of repeating it")
    func reuseMovesToFront() {
        let (store, _, name) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        store.record("😀", kind: .emoji)
        store.record("🚀", kind: .emoji)
        store.record("😀", kind: .emoji)

        #expect(store.recents(for: .emoji) == ["😀", "🚀"])
    }

    @Test("the list is capped")
    func capped() {
        let (store, _, name) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        for i in 0..<(RecentsStore.limit + 10) {
            store.record("g\(i)", kind: .symbols)
        }

        #expect(store.recents(for: .symbols).count == RecentsStore.limit)
        #expect(store.recents(for: .symbols).first == "g\(RecentsStore.limit + 9)")
    }

    @Test("each tab keeps its own list")
    func kindsAreSeparate() {
        let (store, _, name) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        store.record("😀", kind: .emoji)
        store.record("→", kind: .symbols)

        #expect(store.recents(for: .emoji) == ["😀"])
        #expect(store.recents(for: .symbols) == ["→"])
        #expect(store.recents(for: .kaomoji).isEmpty)
    }

    @Test("recents survive a relaunch")
    func persists() {
        let name = "ClipstackTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        RecentsStore(defaults: defaults).record("¯\\_(ツ)_/¯", kind: .kaomoji)

        #expect(RecentsStore(defaults: defaults).recents(for: .kaomoji) == ["¯\\_(ツ)_/¯"])
    }

    @Test("clearing empties only that tab")
    func clear() {
        let (store, _, name) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        store.record("😀", kind: .emoji)
        store.record("→", kind: .symbols)
        store.clear(.emoji)

        #expect(store.recents(for: .emoji).isEmpty)
        #expect(store.recents(for: .symbols) == ["→"])
    }
}
