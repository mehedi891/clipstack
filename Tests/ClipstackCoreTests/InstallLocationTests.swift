import Foundation
import Testing
@testable import ClipstackCore

@Suite("Install location")
struct InstallLocationTests {

    @Test("a normal install is fine", arguments: [
        "/Applications/Clipstack.app",
        "/Users/someone/Applications/Clipstack.app",
        "/Users/someone/Projects/clipstack/build/Clipstack.app",
    ])
    func normalPaths(path: String) {
        #expect(InstallLocation.status(forPath: path) == .normal)
        #expect(!InstallLocation.status(forPath: path).blocksPermissions)
    }

    @Test("running from a mounted disk image is detected")
    func diskImage() {
        let status = InstallLocation.status(forPath: "/Volumes/Clipstack/Clipstack.app")
        #expect(status == .diskImage)
        #expect(status.blocksPermissions)
    }

    @Test("a remounted image with a suffixed name is still detected")
    func remountedDiskImage() {
        // macOS appends a number when the volume name is already taken.
        #expect(InstallLocation.status(forPath: "/Volumes/Clipstack 1/Clipstack.app") == .diskImage)
    }

    @Test("app translocation is detected")
    func translocated() {
        let path = "/private/var/folders/x1/abc/d/AppTranslocation/A1B2-C3D4/d/Clipstack.app"
        let status = InstallLocation.status(forPath: path)
        #expect(status == .translocated)
        #expect(status.blocksPermissions)
    }

    @Test("translocation is reported even when the path also looks like a volume")
    func translocationWins() {
        // Both markers present: translocation is the more specific diagnosis.
        let path = "/Volumes/Clipstack/AppTranslocation/xyz/d/Clipstack.app"
        #expect(InstallLocation.status(forPath: path) == .translocated)
    }
}
