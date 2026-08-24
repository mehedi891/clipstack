import Foundation

/// The clipboard history: ordering, de-duplication, pinning and eviction.
///
/// Deliberately free of AppKit and of any storage concern — `Persistence`
/// is injected — so the rules can be unit tested without a GUI.
@MainActor
public final class ClipboardStore: ObservableObject {

    /// Newest first. Pinned entries are interleaved by recency, exactly as the
    /// Windows panel shows them; being pinned affects eviction, not order.
    @Published public private(set) var items: [ClipboardItem] = []

    /// Maximum number of *unpinned* entries. Pinned entries are never counted
    /// against it and are never evicted.
    public var capacity: Int {
        // Lowering the limit drops entries, which has to reach disk too or the
        // evicted ones reappear on the next launch.
        didSet { if evict() { persist() } }
    }

    private let persistence: PersistenceProtocol?

    public init(capacity: Int = 200, persistence: PersistenceProtocol? = nil) {
        self.capacity = max(1, capacity)
        self.persistence = persistence
    }

    /// Loads previously saved history. Newest-first ordering is re-established
    /// here so a hand-edited or out-of-order store still displays correctly.
    public func load() {
        guard let persistence else { return }
        items = (try? persistence.loadItems())?
            .sorted { $0.createdAt > $1.createdAt } ?? []
    }

    // MARK: - Mutation

    /// Adds an entry, or promotes an identical existing one to the top.
    ///
    /// Returns false when the item was a duplicate, so callers can tell a new
    /// capture from a re-copy.
    @discardableResult
    public func insert(_ item: ClipboardItem) -> Bool {
        if let index = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            var existing = items[index]
            existing.createdAt = item.createdAt
            items.remove(at: index)
            items.insert(existing, at: 0)
            resort()
            persist()
            return false
        }

        items.insert(item, at: 0)
        resort()
        evict()
        persist()
        return true
    }

    public func togglePin(_ id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        // Unpinning can push the total over capacity again.
        evict()
        persist()
    }

    public func delete(_ id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        persistence?.deleteImage(for: removed)
        persist()
    }

    /// Clears history. Pinned entries survive, matching Windows' "Clear all".
    public func clearAll(keepPinned: Bool = true) {
        let removed = items.filter { keepPinned ? !$0.pinned : true }
        removed.forEach { persistence?.deleteImage(for: $0) }
        items = keepPinned ? items.filter(\.pinned) : []
        persist()
    }

    /// Removes every pinned entry. Nothing else is touched.
    ///
    /// The inverse of `clearAll`, for the Pinned tab's "Clear all".
    public func deleteAllPinned() {
        let removed = items.filter(\.pinned)
        guard !removed.isEmpty else { return }

        removed.forEach { persistence?.deleteImage(for: $0) }
        items.removeAll(where: \.pinned)
        persist()
    }

    // MARK: - Queries

    /// Pinned entries, newest first.
    public var pinnedItems: [ClipboardItem] {
        items.filter(\.pinned)
    }

    /// Pinned entries matching a search query.
    public func filteredPinned(by query: String) -> [ClipboardItem] {
        filtered(by: query).filter(\.pinned)
    }

    /// Case- and diacritic-insensitive search over the preview text.
    public func filtered(by query: String) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        return items.filter {
            $0.preview.range(
                of: trimmed,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    // MARK: - Internals

    private func resort() {
        items.sort { $0.createdAt > $1.createdAt }
    }

    /// Drops the oldest unpinned entries beyond `capacity`. Returns whether
    /// anything was removed; callers that own the write to disk check it.
    @discardableResult
    private func evict() -> Bool {
        var unpinnedSeen = 0
        var survivors: [ClipboardItem] = []
        var evicted: [ClipboardItem] = []

        for item in items {   // already newest-first
            if item.pinned {
                survivors.append(item)
                continue
            }
            unpinnedSeen += 1
            if unpinnedSeen <= capacity {
                survivors.append(item)
            } else {
                evicted.append(item)
            }
        }

        guard !evicted.isEmpty else { return false }
        evicted.forEach { persistence?.deleteImage(for: $0) }
        items = survivors
        return true
    }

    private func persist() {
        try? persistence?.saveItems(items)
    }
}
