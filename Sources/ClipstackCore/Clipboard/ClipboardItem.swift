import CryptoKit
import Foundation

/// One entry in the clipboard history.
public struct ClipboardItem: Identifiable, Equatable, Codable, Sendable {

    public enum Kind: String, Codable, Sendable {
        case text
        case richText
        case image
    }

    public let id: UUID
    public let kind: Kind

    /// Plain-text payload, and the pasteboard fallback for rich text.
    public let text: String?
    /// RTF payload, present only for `.richText`.
    public let rtf: Data?
    /// Filename (not a full path) of the PNG in the image directory.
    public let imageFilename: String?

    /// What the list row shows.
    public let preview: String
    public var createdAt: Date
    public var pinned: Bool
    public let sourceBundleID: String?

    /// Identifies duplicate content so re-copying moves the existing entry to
    /// the top instead of adding a second row.
    public let contentHash: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        text: String? = nil,
        rtf: Data? = nil,
        imageFilename: String? = nil,
        preview: String,
        createdAt: Date = Date(),
        pinned: Bool = false,
        sourceBundleID: String? = nil,
        contentHash: String
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.rtf = rtf
        self.imageFilename = imageFilename
        self.preview = preview
        self.createdAt = createdAt
        self.pinned = pinned
        self.sourceBundleID = sourceBundleID
        self.contentHash = contentHash
    }

    // MARK: - Convenience constructors

    public static func text(
        _ value: String,
        createdAt: Date = Date(),
        sourceBundleID: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            kind: .text,
            text: value,
            preview: Self.preview(for: value),
            createdAt: createdAt,
            sourceBundleID: sourceBundleID,
            contentHash: Self.hash(of: Data(value.utf8), kind: .text)
        )
    }

    public static func richText(
        rtf: Data,
        plainText: String,
        createdAt: Date = Date(),
        sourceBundleID: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            kind: .richText,
            text: plainText,
            rtf: rtf,
            preview: Self.preview(for: plainText),
            createdAt: createdAt,
            sourceBundleID: sourceBundleID,
            // Hashed on the visible text, so copying the same words with
            // different styling is not stored twice.
            contentHash: Self.hash(of: Data(plainText.utf8), kind: .richText)
        )
    }

    public static func image(
        filename: String,
        pngData: Data,
        pixelSize: String,
        createdAt: Date = Date(),
        sourceBundleID: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            kind: .image,
            imageFilename: filename,
            preview: "Image \(pixelSize)",
            createdAt: createdAt,
            sourceBundleID: sourceBundleID,
            contentHash: Self.hash(of: pngData, kind: .image)
        )
    }

    // MARK: - Helpers

    /// Collapses whitespace and truncates, so a multi-line copy renders as one
    /// readable row.
    static func preview(for value: String, limit: Int = 200) -> String {
        let collapsed = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        return collapsed.count <= limit
            ? collapsed
            : String(collapsed.prefix(limit)) + "…"
    }

    static func hash(of data: Data, kind: Kind) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
