import Combine
import Foundation
import Testing
@testable import ClipstackCore

@MainActor
@Suite("AppSettings")
struct AppSettingsTests {

    /// Each test gets its own defaults suite so nothing leaks into the real app.
    private func makeSettings(
        _ seed: (UserDefaults) -> Void = { _ in }
    ) throws -> (AppSettings, UserDefaults, String) {
        let name = "ClipstackTests-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        seed(defaults)
        return (AppSettings(defaults: defaults), defaults, name)
    }

    @Test("capacity defaults to 200 when nothing is saved")
    func defaultCapacity() throws {
        let (settings, _, name) = try makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        #expect(settings.capacity == AppSettings.defaultCapacity)
    }

    /// Regression: the setter used to clamp inside a `didSet` on an `@Published`
    /// property, which re-entered the setter and crashed with a stack overflow
    /// the moment the Settings stepper was touched. Reaching the expectation at
    /// all is most of what this asserts.
    @Test("changing capacity does not recurse, and persists")
    func capacityIsSettable() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        settings.capacity = 210

        #expect(settings.capacity == 210)
        #expect(defaults.integer(forKey: "capacity") == 210)
    }

    @Test("repeated changes stay stable", arguments: [10, 190, 200, 210, 1000])
    func repeatedChanges(_ value: Int) throws {
        let (settings, _, name) = try makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        for _ in 0..<3 { settings.capacity = value }

        #expect(settings.capacity == value)
    }

    @Test("out-of-range values are clamped, not stored raw")
    func clampsOutOfRange() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        settings.capacity = 5
        #expect(settings.capacity == AppSettings.capacityRange.lowerBound)

        settings.capacity = 50_000
        #expect(settings.capacity == AppSettings.capacityRange.upperBound)
        #expect(defaults.integer(forKey: "capacity") == AppSettings.capacityRange.upperBound)
    }

    @Test("a saved capacity is restored, clamped if it is out of range")
    func restoresSavedCapacity() throws {
        let (settings, _, name) = try makeSettings { $0.set(350, forKey: "capacity") }
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        #expect(settings.capacity == 350)

        let (wide, _, wideName) = try makeSettings { $0.set(9_999, forKey: "capacity") }
        defer { UserDefaults.standard.removePersistentDomain(forName: wideName) }
        #expect(wide.capacity == AppSettings.capacityRange.upperBound)
    }

    /// The stepper writes through this property on every click, so a change
    /// notification has to reach SwiftUI or the label would freeze.
    @Test("a capacity change publishes a change notification")
    func publishesChanges() throws {
        let (settings, _, name) = try makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        var notifications = 0
        let token = settings.objectWillChange.sink { _ in notifications += 1 }
        defer { token.cancel() }

        settings.capacity = 300
        #expect(notifications == 1)

        // Setting the same value again is a no-op, including for observers.
        settings.capacity = 300
        #expect(notifications == 1)
    }

    @Test("the other settings persist too")
    func otherSettingsPersist() throws {
        let (settings, defaults, name) = try makeSettings()
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        settings.historyEnabled = true
        settings.launchAtLogin = true

        #expect(defaults.bool(forKey: "historyEnabled"))
        #expect(defaults.bool(forKey: "launchAtLogin"))
    }
}
