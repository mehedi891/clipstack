import Foundation
import Testing
@testable import ClipstackCore

/// The launch agent is the macOS 12 path for "Open at login", where
/// `SMAppService` does not exist. `launchd` reads this plist at login, so the
/// keys have to be exactly right — a typo means the app silently never starts.
@Suite("Launch agent property list")
struct LaunchAgentTests {

    @Test("runs the executable it is given, at login")
    func contents() {
        let plist = LaunchAgent.contents(executablePath: "/Applications/Clipstack.app/Contents/MacOS/Clipstack")

        #expect(plist["Label"] as? String == "com.efoli.Clipstack")
        #expect(plist["ProgramArguments"] as? [String] == ["/Applications/Clipstack.app/Contents/MacOS/Clipstack"])
        #expect(plist["RunAtLoad"] as? Bool == true)
    }

    @Test("does not restart the app after the user quits it")
    func doesNotKeepAlive() {
        let plist = LaunchAgent.contents(executablePath: "/tmp/Clipstack")

        #expect(plist["KeepAlive"] as? Bool == false)
    }

    @Test("serialises to a plist launchd can read")
    func serialises() throws {
        let plist = LaunchAgent.contents(executablePath: "/tmp/Clipstack")

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let parsed = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any]

        #expect(parsed?["Label"] as? String == "com.efoli.Clipstack")
    }

    @Test("lands in ~/Library/LaunchAgents, where launchd looks")
    func location() {
        #expect(LaunchAgent.url.path.hasSuffix("/Library/LaunchAgents/com.efoli.Clipstack.plist"))
    }
}
