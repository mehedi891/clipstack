import Foundation

/// Moves data left behind by the app's former name, "MacClipboard".
///
/// Renaming changed both the Application Support directory and the bundle
/// identifier that names the preferences domain, so without this a user's
/// history, pins and settings would silently vanish on upgrade.
///
/// Runs once: after a successful move the old locations no longer exist, and
/// every step is a no-op when there is nothing to migrate.
public enum LegacyMigration {

    public static let legacyDirectoryName = "MacClipboard"
    public static let legacyDefaultsSuite = "com.efoli.MacClipboard"

    /// Keys worth carrying over. Anything else is derivable or disposable.
    private static let defaultsKeys = [
        "historyEnabled", "capacity", "launchAtLogin", "hotkey",
        "recent.emoji", "recent.kaomoji", "recent.symbols",
    ]

    public struct Result: Equatable {
        public var movedDirectory = false
        public var migratedDefaultKeys: [String] = []

        public var didAnything: Bool { movedDirectory || !migratedDefaultKeys.isEmpty }
    }

    @discardableResult
    public static func run(
        newDirectory: URL = SQLitePersistence.defaultDirectory,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> Result {
        var result = Result()
        result.movedDirectory = migrateDirectory(to: newDirectory, fileManager: fileManager)
        result.migratedDefaultKeys = migrateDefaults(into: defaults)
        return result
    }

    /// Moves the old support directory only when the new one is absent, so a
    /// fresh install is never overwritten by stale data.
    static func migrateDirectory(to newDirectory: URL, fileManager: FileManager) -> Bool {
        let legacy = newDirectory
            .deletingLastPathComponent()
            .appendingPathComponent(legacyDirectoryName, isDirectory: true)

        guard fileManager.fileExists(atPath: legacy.path) else { return false }

        // SQLitePersistence creates the new directory eagerly, so "already
        // migrated" means it holds a database — not merely that it exists.
        let existingDatabase = newDirectory.appendingPathComponent("history.sqlite")
        guard !fileManager.fileExists(atPath: existingDatabase.path) else { return false }

        do {
            // Remove the empty placeholder the persistence layer may have made,
            // since moveItem refuses to overwrite.
            if fileManager.fileExists(atPath: newDirectory.path) {
                let contents = try? fileManager.contentsOfDirectory(atPath: newDirectory.path)
                if contents?.isEmpty ?? false {
                    try fileManager.removeItem(at: newDirectory)
                } else {
                    return false   // unexpected contents; leave both alone
                }
            }

            try fileManager.moveItem(at: legacy, to: newDirectory)
            return true
        } catch {
            NSLog("Clipstack: could not migrate data from %@: %@", legacy.path, "\(error)")
            return false
        }
    }

    /// Copies preferences across, skipping any the user has already set under
    /// the new identifier.
    static func migrateDefaults(into defaults: UserDefaults) -> [String] {
        guard let legacy = UserDefaults(suiteName: legacyDefaultsSuite) else { return [] }

        var migrated: [String] = []
        for key in defaultsKeys {
            guard defaults.object(forKey: key) == nil,
                  let value = legacy.object(forKey: key)
            else { continue }

            defaults.set(value, forKey: key)
            migrated.append(key)
        }
        return migrated
    }
}
