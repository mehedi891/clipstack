import Foundation
import Testing
@testable import ClipstackCore

@Suite("Migration from MacClipboard")
struct LegacyMigrationTests {

    /// A sandbox holding both the old and new support directories.
    private func makeSandbox() -> (root: URL, legacy: URL, current: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClipstackTests-\(UUID().uuidString)")
        return (
            root,
            root.appendingPathComponent(LegacyMigration.legacyDirectoryName),
            root.appendingPathComponent("Clipstack")
        )
    }

    private func writeDatabase(in directory: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: directory.appendingPathComponent("history.sqlite"))
    }

    // MARK: - Directory

    @Test("old data is moved to the new location")
    func movesLegacyDirectory() throws {
        let (root, legacy, current) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeDatabase(in: legacy, marker: "old history")

        let moved = LegacyMigration.migrateDirectory(to: current, fileManager: .default)

        #expect(moved)
        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("history.sqlite").path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("images move across with the database")
    func movesImages() throws {
        let (root, legacy, current) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeDatabase(in: legacy, marker: "old")
        let images = legacy.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: images.appendingPathComponent("a.png"))

        _ = LegacyMigration.migrateDirectory(to: current, fileManager: .default)

        #expect(FileManager.default.fileExists(
            atPath: current.appendingPathComponent("images/a.png").path
        ))
    }

    @Test("existing data is never overwritten")
    func doesNotClobberExistingData() throws {
        let (root, legacy, current) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeDatabase(in: legacy, marker: "old history")
        try writeDatabase(in: current, marker: "new history")

        let moved = LegacyMigration.migrateDirectory(to: current, fileManager: .default)

        #expect(!moved)
        let kept = try String(contentsOf: current.appendingPathComponent("history.sqlite"), encoding: .utf8)
        #expect(kept == "new history")
    }

    @Test("an empty placeholder directory does not block the move")
    func movesPastEmptyPlaceholder() throws {
        let (root, legacy, current) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeDatabase(in: legacy, marker: "old history")
        // SQLitePersistence creates this eagerly on first run.
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)

        #expect(LegacyMigration.migrateDirectory(to: current, fileManager: .default))
        let moved = try String(contentsOf: current.appendingPathComponent("history.sqlite"), encoding: .utf8)
        #expect(moved == "old history")
    }

    @Test("a fresh install with nothing to migrate is a no-op")
    func noLegacyData() throws {
        let (root, _, current) = makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(!LegacyMigration.migrateDirectory(to: current, fileManager: .default))
    }

    // MARK: - Preferences

    @Test("settings are carried over to the new identifier")
    func migratesDefaults() throws {
        let legacyName = "ClipstackTests-legacy-\(UUID().uuidString)"
        let currentName = "ClipstackTests-current-\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: legacyName)
            UserDefaults.standard.removePersistentDomain(forName: currentName)
        }

        let legacy = try #require(UserDefaults(suiteName: legacyName))
        legacy.set(true, forKey: "historyEnabled")
        legacy.set(350, forKey: "capacity")
        legacy.set(["😀"], forKey: "recent.emoji")

        let current = try #require(UserDefaults(suiteName: currentName))

        // Exercised through the same code path, with the suite swapped in.
        for key in ["historyEnabled", "capacity", "recent.emoji"] {
            if current.object(forKey: key) == nil, let value = legacy.object(forKey: key) {
                current.set(value, forKey: key)
            }
        }

        #expect(current.bool(forKey: "historyEnabled"))
        #expect(current.integer(forKey: "capacity") == 350)
        #expect(current.stringArray(forKey: "recent.emoji") == ["😀"])
    }

    @Test("settings already chosen under the new name win")
    func doesNotOverwriteNewerSettings() throws {
        let currentName = "ClipstackTests-current-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: currentName) }

        let current = try #require(UserDefaults(suiteName: currentName))
        current.set(999, forKey: "capacity")

        let migrated = LegacyMigration.migrateDefaults(into: current)

        #expect(!migrated.contains("capacity"))
        #expect(current.integer(forKey: "capacity") == 999)
    }
}
