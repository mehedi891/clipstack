import Foundation

/// User preferences, persisted in UserDefaults.
@MainActor
public final class AppSettings: ObservableObject {

    private enum Key {
        static let historyEnabled = "historyEnabled"
        static let capacity = "capacity"
        static let launchAtLogin = "launchAtLogin"
        static let hotkey = "hotkey"
    }

    public static let defaultCapacity = 200
    public static let capacityRange = 10...1000

    private let defaults: UserDefaults

    /// Mirrors the Windows "Turn on clipboard history" switch. Off until the
    /// user opts in, so nothing is recorded behind their back on first launch.
    @Published public var historyEnabled: Bool {
        didSet { defaults.set(historyEnabled, forKey: Key.historyEnabled) }
    }

    /// Maximum number of unpinned entries kept.
    @Published public var capacity: Int {
        didSet {
            capacity = capacity.clamped(to: Self.capacityRange)
            defaults.set(capacity, forKey: Key.capacity)
        }
    }

    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    /// Shortcut that opens the panel. Defaults to Cmd+Shift+V.
    @Published public var hotkey: GlobalHotkey.Combo {
        didSet {
            guard let data = try? JSONEncoder().encode(hotkey) else { return }
            defaults.set(data, forKey: Key.hotkey)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.historyEnabled = defaults.bool(forKey: Key.historyEnabled)
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)

        if let data = defaults.data(forKey: Key.hotkey),
           let saved = try? JSONDecoder().decode(GlobalHotkey.Combo.self, from: data) {
            self.hotkey = saved
        } else {
            self.hotkey = .commandShiftV
        }

        let stored = defaults.integer(forKey: Key.capacity)
        self.capacity = stored == 0
            ? Self.defaultCapacity
            : stored.clamped(to: Self.capacityRange)
    }
}

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
