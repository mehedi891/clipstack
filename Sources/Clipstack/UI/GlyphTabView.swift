import ClipstackCore
import SwiftUI

/// Shared grid picker for the kaomoji and symbols tabs, which differ only in
/// their catalogue and cell width.
struct GlyphTabView: View {
    let title: String
    let categories: [SymbolCategory]
    let kind: RecentsStore.Kind
    /// Kaomoji are wide strings; symbols are single characters.
    let wideCells: Bool
    let onSelect: (String) -> Void

    @EnvironmentObject private var recents: RecentsStore
    @State private var query = ""

    private var matches: [String]? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }

        // Symbols have no names to search, so match the glyph itself and the
        // category name — enough to find "arrow" or "currency".
        return categories.flatMap { category -> [String] in
            category.name.range(of: needle, options: .caseInsensitive) != nil
                ? category.symbols
                : category.symbols.filter { $0.contains(needle) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: title) { EmptyView() }

            SearchField(text: $query, placeholder: "Search \(title.lowercased())")
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.sm)

            if let matches, matches.isEmpty {
                EmptyState(
                    icon: "magnifyingglass",
                    title: "No matches",
                    message: "Nothing in \(title.lowercased()) matches “\(query)”."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.md) {
                        if let matches {
                            GlyphSection(name: "Results", glyphs: matches, wideCells: wideCells, onSelect: select)
                        } else {
                            let recent = recents.recents(for: kind)
                            if !recent.isEmpty {
                                GlyphSection(name: "Recently used", glyphs: recent, wideCells: wideCells, onSelect: select)
                            }
                            ForEach(categories) { category in
                                GlyphSection(name: category.name, glyphs: category.symbols, wideCells: wideCells, onSelect: select)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, Theme.Space.md)
                }
            }
        }
    }

    private func select(_ glyph: String) {
        recents.record(glyph, kind: kind)
        onSelect(glyph)
    }
}

struct GlyphSection: View {
    let name: String
    let glyphs: [String]
    let wideCells: Bool
    let onSelect: (String) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: wideCells ? 100 : 36), spacing: Theme.Space.xs)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel(name)

            LazyVGrid(columns: columns, spacing: Theme.Space.xs) {
                // Indexed: the recents section can repeat a glyph that also
                // appears in a category, so the glyph is not a unique id.
                ForEach(Array(glyphs.enumerated()), id: \.offset) { _, glyph in
                    GlyphCell(glyph: glyph, wide: wideCells) { onSelect(glyph) }
                }
            }
        }
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

private struct GlyphCell: View {
    let glyph: String
    let wide: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: wide ? 11 : 16))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(isHovered ? Theme.cardHover : Theme.card)
                )
                .hairline(Theme.Radius.sm, color: isHovered ? Theme.accentStart.opacity(0.5) : Theme.border)
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in
            withAnimation(Theme.quick) { isHovered = hovering }
        }
        .help(glyph)
        .accessibilityLabel(glyph)
    }
}
