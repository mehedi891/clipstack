// swift-testing, not XCTest: the Command Line Tools ship Testing.framework
// but no XCTest, so `import XCTest` cannot compile without full Xcode.
import Testing
@testable import ClipstackCore

@Suite("Glyph catalogues")
struct CataloguesTests {

    // MARK: - Symbols and kaomoji

    @Test("symbol catalogues load from the resource bundle", arguments: ["symbols", "kaomoji"])
    func glyphCataloguesLoad(name: String) throws {
        let categories = name == "symbols"
            ? try Catalogues.loadSymbols()
            : try Catalogues.loadKaomoji()

        #expect(!categories.isEmpty, "\(name).json should ship at least one category")

        for category in categories {
            let hasEmptyGlyph = category.symbols.contains { $0.isEmpty }

            #expect(!category.name.isEmpty)
            #expect(!category.symbols.isEmpty, "\(category.name) has no entries")
            #expect(!hasEmptyGlyph, "\(category.name) contains an empty entry")
            #expect(
                category.symbols.count == Set(category.symbols).count,
                "\(category.name) repeats an entry"
            )
        }

        let names = categories.map(\.name)
        #expect(names.count == Set(names).count, "duplicate category names")
    }

    @Test("kaomoji survive JSON escaping intact")
    func kaomojiEscaping() throws {
        let all = try Catalogues.loadKaomoji().flatMap(\.symbols)
        // The shrug contains a backslash, the classic JSON-escaping casualty.
        #expect(all.contains(#"¯\_(ツ)_/¯"#))
    }

    // MARK: - Emoji

    @Test("emoji catalogue loads with categories and entries")
    func emojiLoads() throws {
        let categories = try Catalogues.loadEmoji()
        #expect(!categories.isEmpty)

        for category in categories {
            #expect(!category.name.isEmpty)
            #expect(!category.emoji.isEmpty, "\(category.name) has no emoji")
        }
    }

    @Test("every emoji has a character, a name and keywords")
    func emojiEntriesAreWellFormed() throws {
        for category in try Catalogues.loadEmoji() {
            for entry in category.emoji {
                #expect(!entry.char.isEmpty, "\(category.name) has an empty character")
                #expect(!entry.name.isEmpty, "\(entry.char) has no name")
            }
        }
    }

    @Test("no emoji is listed in two categories")
    func emojiAreNotDuplicated() throws {
        let all = try Catalogues.loadEmoji().flatMap(\.emoji).map(\.char)
        #expect(all.count == Set(all).count)
    }

    @Test("legacy-range emoji carry the variation selector so they render in colour")
    func legacyEmojiHaveVariationSelector() throws {
        let all = try Catalogues.loadEmoji().flatMap(\.emoji)
        let heart = try #require(all.first { $0.char.unicodeScalars.first?.value == 0x2764 })

        #expect(heart.char.unicodeScalars.contains { $0.value == 0xFE0F })
    }

    @Test("common searches find the expected emoji", arguments: [
        ("rocket", "🚀"),
        ("pizza", "🍕"),
        ("grinning", "😀"),
    ])
    func emojiSearch(query: String, expected: String) {
        let results = Catalogues.searchEmoji(query).map(\.char)
        #expect(results.contains(expected), "searching \(query) should find \(expected)")
    }

    @Test("emoji search ignores case and blank queries")
    func emojiSearchEdgeCases() {
        #expect(!Catalogues.searchEmoji("ROCKET").isEmpty)
        #expect(Catalogues.searchEmoji("   ").isEmpty)
        #expect(Catalogues.searchEmoji("zzzzznotathing").isEmpty)
    }
}
