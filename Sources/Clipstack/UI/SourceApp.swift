import AppKit

/// Resolves the app a clip was copied from, for display in a row.
///
/// Lookups hit the file system, so results are cached: the list re-renders on
/// every hover and keystroke, and the same handful of apps recur throughout the
/// history.
@MainActor
enum SourceApp {

    private struct Entry {
        let name: String
        let icon: NSImage?
    }

    private static var cache: [String: Entry] = [:]

    static func name(for bundleID: String?) -> String? {
        entry(for: bundleID)?.name
    }

    static func icon(for bundleID: String?) -> NSImage? {
        entry(for: bundleID)?.icon
    }

    private static func entry(for bundleID: String?) -> Entry? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = cache[bundleID] { return cached }

        // The app may have been uninstalled since the clip was captured; fall
        // back to the last identifier component rather than showing nothing.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            let fallback = Entry(name: bundleID.split(separator: ".").last.map(String.init) ?? bundleID, icon: nil)
            cache[bundleID] = fallback
            return fallback
        }

        let entry = Entry(
            name: FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: ""),
            icon: NSWorkspace.shared.icon(forFile: url.path)
        )
        cache[bundleID] = entry
        return entry
    }
}
