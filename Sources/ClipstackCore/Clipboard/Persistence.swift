import Foundation
import SQLite3

/// Storage seam for `ClipboardStore`, so history rules can be tested against an
/// in-memory double.
public protocol PersistenceProtocol: AnyObject {
    func loadItems() throws -> [ClipboardItem]
    func saveItems(_ items: [ClipboardItem]) throws

    /// Writes PNG bytes to the image directory and returns the filename.
    func saveImage(_ pngData: Data) throws -> String
    func imageURL(forFilename filename: String) -> URL
    func deleteImage(for item: ClipboardItem)
}

public enum PersistenceError: Error, CustomStringConvertible {
    case open(String)
    case sql(String)

    public var description: String {
        switch self {
        case .open(let m): return "Could not open the history database: \(m)"
        case .sql(let m): return "History database error: \(m)"
        }
    }
}

/// SQLite-backed history.
///
/// Uses the SDK's libsqlite3 directly so the app has no external dependencies.
/// Saves rewrite the whole table inside one transaction: at the few-hundred-row
/// scale this app works at, that is faster than tracking per-row deltas and has
/// far less to get wrong.
public final class SQLitePersistence: PersistenceProtocol {

    private var db: OpaquePointer?
    private let directory: URL
    private let imageDirectory: URL

    /// Required when binding Swift-owned bytes: SQLite must copy them, because
    /// the buffer does not outlive the call.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// `~/Library/Application Support/Clipstack`, unless
    /// `CLIPSTACK_DEBUG_STORAGE` names somewhere else.
    ///
    /// The override exists for the screenshot script, which points it at a
    /// throwaway directory holding staged demo entries — otherwise every
    /// capture for the README would expose whatever the author had really
    /// copied that day.
    public static var defaultDirectory: URL {
        directory(from: ProcessInfo.processInfo.environment)
    }

    static let storageOverrideKey = "CLIPSTACK_DEBUG_STORAGE"

    /// Split out from `defaultDirectory` so the override can be tested without
    /// touching the process environment.
    static func directory(from environment: [String: String]) -> URL {
        if let override = environment[storageOverrideKey], !override.isEmpty {
            return URL(
                fileURLWithPath: (override as NSString).expandingTildeInPath,
                isDirectory: true
            )
        }

        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipstack", isDirectory: true)
    }

    public init(directory: URL = SQLitePersistence.defaultDirectory) throws {
        self.directory = directory
        self.imageDirectory = directory.appendingPathComponent("images", isDirectory: true)

        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)

        let dbURL = directory.appendingPathComponent("history.sqlite")
        guard sqlite3_open_v2(
            dbURL.path,
            &db,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            throw PersistenceError.open(lastMessage)
        }

        try exec("PRAGMA journal_mode=WAL;")
        try exec("""
            CREATE TABLE IF NOT EXISTS items (
                id             TEXT PRIMARY KEY,
                kind           TEXT NOT NULL,
                text           TEXT,
                rtf            BLOB,
                imageFilename  TEXT,
                preview        TEXT NOT NULL,
                createdAt      REAL NOT NULL,
                pinned         INTEGER NOT NULL,
                sourceBundleID TEXT,
                contentHash    TEXT NOT NULL
            );
            """)
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    // MARK: - Items

    public func loadItems() throws -> [ClipboardItem] {
        let sql = """
            SELECT id, kind, text, rtf, imageFilename, preview,
                   createdAt, pinned, sourceBundleID, contentHash
            FROM items ORDER BY createdAt DESC;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.sql(lastMessage)
        }
        defer { sqlite3_finalize(statement) }

        var result: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let idText = column(statement, 0),
                let uuid = UUID(uuidString: idText),
                let kindText = column(statement, 1),
                let kind = ClipboardItem.Kind(rawValue: kindText),
                let preview = column(statement, 5),
                let hash = column(statement, 9)
            else { continue }   // skip rows a future/older schema left malformed

            result.append(
                ClipboardItem(
                    id: uuid,
                    kind: kind,
                    text: column(statement, 2),
                    rtf: blob(statement, 3),
                    imageFilename: column(statement, 4),
                    preview: preview,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                    pinned: sqlite3_column_int(statement, 7) != 0,
                    sourceBundleID: column(statement, 8),
                    contentHash: hash
                )
            )
        }
        return result
    }

    public func saveItems(_ items: [ClipboardItem]) throws {
        try exec("BEGIN IMMEDIATE;")
        do {
            try exec("DELETE FROM items;")

            let sql = """
                INSERT INTO items
                  (id, kind, text, rtf, imageFilename, preview,
                   createdAt, pinned, sourceBundleID, contentHash)
                VALUES (?,?,?,?,?,?,?,?,?,?);
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw PersistenceError.sql(lastMessage)
            }
            defer { sqlite3_finalize(statement) }

            for item in items {
                sqlite3_reset(statement)
                bind(statement, 1, item.id.uuidString)
                bind(statement, 2, item.kind.rawValue)
                bind(statement, 3, item.text)
                bind(statement, 4, item.rtf)
                bind(statement, 5, item.imageFilename)
                bind(statement, 6, item.preview)
                sqlite3_bind_double(statement, 7, item.createdAt.timeIntervalSince1970)
                sqlite3_bind_int(statement, 8, item.pinned ? 1 : 0)
                bind(statement, 9, item.sourceBundleID)
                bind(statement, 10, item.contentHash)

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw PersistenceError.sql(lastMessage)
                }
            }
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    // MARK: - Images

    public func saveImage(_ pngData: Data) throws -> String {
        let filename = UUID().uuidString + ".png"
        try pngData.write(to: imageDirectory.appendingPathComponent(filename))
        return filename
    }

    public func imageURL(forFilename filename: String) -> URL {
        imageDirectory.appendingPathComponent(filename)
    }

    public func deleteImage(for item: ClipboardItem) {
        guard let filename = item.imageFilename else { return }
        try? FileManager.default.removeItem(at: imageURL(forFilename: filename))
    }

    // MARK: - SQLite helpers

    private var lastMessage: String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw PersistenceError.sql(lastMessage)
        }
    }

    private func column(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    private func blob(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Data?) {
        if let value, !value.isEmpty {
            _ = value.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), Self.transient)
            }
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
}
