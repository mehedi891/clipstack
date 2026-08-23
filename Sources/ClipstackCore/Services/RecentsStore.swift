import Foundation

/// Most-recently-used glyphs per picker tab, so the things you actually use
/// stay one click away.
@MainActor
public final class RecentsStore: ObservableObject {

    public enum Kind: String, CaseIterable, Sendable {
        case emoji
        case kaomoji
        case symbols

        var defaultsKey: String { "recent.\(rawValue)" }
    }

    public static let limit = 24

    private let defaults: UserDefaults
    @Published private var storage: [Kind: [String]] = [:]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for kind in Kind.allCases {
            storage[kind] = defaults.stringArray(forKey: kind.defaultsKey) ?? []
        }
    }

    public func recents(for kind: Kind) -> [String] {
        storage[kind] ?? []
    }

    /// Moves an existing entry to the front rather than repeating it.
    public func record(_ value: String, kind: Kind) {
        var list = storage[kind] ?? []
        list.removeAll { $0 == value }
        list.insert(value, at: 0)
        if list.count > Self.limit {
            list = Array(list.prefix(Self.limit))
        }
        storage[kind] = list
        defaults.set(list, forKey: kind.defaultsKey)
    }

    public func clear(_ kind: Kind) {
        storage[kind] = []
        defaults.removeObject(forKey: kind.defaultsKey)
    }
}
