import ClipstackCore
import SwiftUI

struct EmojiTabView: View {
    let onSelect: (String) -> Void

    @EnvironmentObject private var recents: RecentsStore
    @State private var query = ""

    private var matches: [Emoji]? {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : Catalogues.searchEmoji(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Emoji") { EmptyView() }

            SearchField(text: $query, placeholder: "Search emoji")
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.sm)

            if let matches, matches.isEmpty {
                EmptyState(
                    icon: "magnifyingglass",
                    title: "No matches",
                    message: "No emoji matches “\(query)”."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.md) {
                        if let matches {
                            EmojiSection(name: "Results", emoji: matches, onSelect: select)
                        } else {
                            let recent = recents.recents(for: .emoji)
                            if !recent.isEmpty {
                                EmojiSection(
                                    name: "Recently used",
                                    emoji: recent.map { Emoji(char: $0, name: $0, keywords: "") },
                                    onSelect: select
                                )
                            }
                            ForEach(Catalogues.emoji) { category in
                                EmojiSection(name: category.name, emoji: category.emoji, onSelect: select)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, Theme.Space.md)
                }
            }
        }
    }

    private func select(_ emoji: Emoji) {
        recents.record(emoji.char, kind: .emoji)
        onSelect(emoji.char)
    }
}

private struct EmojiSection: View {
    let name: String
    let emoji: [Emoji]
    let onSelect: (Emoji) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel(name)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: Theme.Space.xxs)], spacing: Theme.Space.xxs) {
                // Indexed: recents can repeat a character that also appears in
                // a category, so the glyph is not a unique id here.
                ForEach(Array(emoji.enumerated()), id: \.offset) { _, item in
                    EmojiCell(emoji: item) { onSelect(item) }
                }
            }
        }
    }
}

private struct EmojiCell: View {
    let emoji: Emoji
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(emoji.char)
                .font(.system(size: 19))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(isHovered ? Theme.cardHover : .clear)
                )
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in
            withAnimation(Theme.quick) { isHovered = hovering }
        }
        .help(emoji.name)
        .accessibilityLabel(emoji.name)
    }
}
