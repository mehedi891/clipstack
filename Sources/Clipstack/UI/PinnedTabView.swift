import ClipstackCore
import SwiftUI

/// Pinned entries only.
///
/// Pinned items are exempt from the history limit, so this tab is the durable
/// shelf: things kept deliberately, separate from the churn of recent copies.
struct PinnedTabView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: ClipboardStore

    @State private var query = ""
    @State private var selectedID: ClipboardItem.ID?
    @State private var isConfirmingClear = false
    @FocusState private var searchFocused: Bool

    let onSelect: (ClipboardItem) -> Void

    private var pinned: [ClipboardItem] {
        store.filteredPinned(by: query)
    }

    private var totalPinned: Int {
        store.pinnedItems.count
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                title: "Pinned",
                subtitle: totalPinned > 0 ? "\(totalPinned)" : nil
            ) {
                if totalPinned > 0 {
                    GhostButton(title: "Clear all", role: .destructive) {
                        withAnimation(Theme.quick) { isConfirmingClear = true }
                    }
                }
            }

            if isConfirmingClear {
                ConfirmBar(
                    message: "Delete all \(totalPinned) pinned items?",
                    confirmTitle: "Delete",
                    onConfirm: {
                        withAnimation(Theme.spring) {
                            store.deleteAllPinned()
                            isConfirmingClear = false
                        }
                    },
                    onCancel: {
                        withAnimation(Theme.quick) { isConfirmingClear = false }
                    }
                )
            }

            if totalPinned == 0 {
                EmptyState(
                    icon: "pin",
                    title: "No pinned items",
                    message: "Pin an item from the Clipboard tab and it stays here for good."
                )
            } else {
                SearchField(
                    text: $query,
                    placeholder: "Search pinned",
                    focus: $searchFocused,
                    onSubmit: activateSelection
                )
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.sm)

                list
            }
        }
        .onArrowKeys { key in moveSelection(by: key == .up ? -1 : 1) }
        .onAppear { selectedID = pinned.first?.id }
        .onValueChange(of: query) { _ in selectedID = pinned.first?.id }
        // Leaving the tab abandons a pending confirmation, so returning to it
        // never presents a stale "are you sure?".
        .onDisappear { isConfirmingClear = false }
    }

    @ViewBuilder
    private var list: some View {
        if pinned.isEmpty {
            EmptyState(
                icon: "magnifyingglass",
                title: "No matches",
                message: "No pinned item matches “\(query)”."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Space.xs) {
                        ForEach(pinned) { item in
                            ClipboardRow(
                                item: item,
                                thumbnail: model.image(for: item),
                                isSelected: item.id == selectedID,
                                onSelect: { onSelect(item) },
                                // Unpinning here removes it from this tab but
                                // keeps the content in history.
                                onTogglePin: {
                                    withAnimation(Theme.spring) { store.togglePin(item.id) }
                                },
                                onDelete: {
                                    withAnimation(Theme.spring) { store.delete(item.id) }
                                }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, Theme.Space.md)
                }
                .onValueChange(of: selectedID) { id in
                    guard let id else { return }
                    withAnimation(Theme.quick) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    /// Returns whether the key was used, so an unhandled arrow still reaches
    /// whatever is focused.
    private func moveSelection(by offset: Int) -> Bool {
        guard !pinned.isEmpty else { return false }

        let current = pinned.firstIndex { $0.id == selectedID } ?? 0
        let next = (current + offset).clamped(to: 0...(pinned.count - 1))
        selectedID = pinned[next].id
        return true
    }

    private func activateSelection() {
        guard let item = pinned.first(where: { $0.id == selectedID }) ?? pinned.first else { return }
        onSelect(item)
    }
}
