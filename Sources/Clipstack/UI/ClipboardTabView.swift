import ClipstackCore
import SwiftUI

struct ClipboardTabView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var settings: AppSettings

    @State private var query = ""
    @State private var selectedID: ClipboardItem.ID?
    @FocusState private var searchFocused: Bool

    let onSelect: (ClipboardItem) -> Void

    private var results: [ClipboardItem] { store.filtered(by: query) }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                title: "Clipboard",
                subtitle: settings.historyEnabled && !store.items.isEmpty
                    ? "\(store.items.count)"
                    : nil
            ) {
                if settings.historyEnabled && !store.items.isEmpty {
                    GhostButton(title: "Clear all") {
                        withAnimation(Theme.spring) { store.clearAll() }
                    }
                }
            }

            if !settings.historyEnabled {
                EmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "Let's get started",
                    message: "Turn on clipboard history to copy and view multiple items.",
                    action: ("Turn on", { withAnimation(Theme.spring) { model.setHistoryEnabled(true) } })
                )
            } else if store.items.isEmpty {
                EmptyState(
                    icon: "doc.on.clipboard",
                    title: "Nothing copied yet",
                    message: "Copy something and it will show up here."
                )
            } else {
                SearchField(
                    text: $query,
                    placeholder: "Search history",
                    focus: $searchFocused,
                    onSubmit: activateSelection
                )
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.sm)

                list
            }
        }
        // Arrow keys reach here from the focused search field, because key
        // presses it does not consume propagate up to ancestors.
        .onArrowKeys { key in moveSelection(by: key == .up ? -1 : 1) }
        .onAppear {
            searchFocused = true
            selectedID = results.first?.id
        }
        .onValueChange(of: query) { _ in
            // Keep the highlight on something that is actually visible.
            selectedID = results.first?.id
        }
    }

    @ViewBuilder
    private var list: some View {
        if results.isEmpty {
            EmptyState(
                icon: "magnifyingglass",
                title: "No matches",
                message: "Nothing in the history matches “\(query)”."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Space.xs) {
                        ForEach(results) { item in
                            ClipboardRow(
                                item: item,
                                thumbnail: model.image(for: item),
                                isSelected: item.id == selectedID,
                                onSelect: { onSelect(item) },
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

    // MARK: - Keyboard

    /// Returns whether the key was used, so an unhandled arrow still reaches
    /// whatever is focused.
    private func moveSelection(by offset: Int) -> Bool {
        guard !results.isEmpty else { return false }

        let current = results.firstIndex { $0.id == selectedID } ?? 0
        let next = (current + offset).clamped(to: 0...(results.count - 1))
        selectedID = results[next].id
        return true
    }

    private func activateSelection() {
        guard let item = results.first(where: { $0.id == selectedID }) ?? results.first else { return }
        onSelect(item)
    }
}
