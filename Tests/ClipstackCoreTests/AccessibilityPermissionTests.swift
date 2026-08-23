import Foundation
import Testing
@testable import ClipstackCore

@Suite("Resetting Accessibility permission")
struct AccessibilityPermissionTests {

    @Test("a single cleared record is reported")
    func oneRecord() {
        let outcome = AccessibilityPermission.parseReset(
            output: "Successfully reset Accessibility approval status for com.efoli.Clipstack\n",
            exitCode: 0
        )
        #expect(outcome == .cleared(records: 1))
        #expect(outcome.succeeded)
    }

    @Test("conflicting duplicate records are counted")
    func duplicateRecords() {
        // The real symptom: two entries, so the switch looks on but does nothing.
        let output = """
            Successfully reset Accessibility approval status for com.efoli.Clipstack
            Successfully reset Accessibility approval status for com.efoli.Clipstack
            """
        #expect(AccessibilityPermission.parseReset(output: output, exitCode: 0) == .cleared(records: 2))
    }

    @Test("no records is not a failure")
    func nothingRegistered() {
        let outcome = AccessibilityPermission.parseReset(output: "", exitCode: 0)
        #expect(outcome == .nothingToClear)
        #expect(outcome.succeeded)
    }

    @Test("a non-zero exit is reported with tccutil's own message")
    func failure() {
        let outcome = AccessibilityPermission.parseReset(
            output: "tccutil: Failed to reset database\n",
            exitCode: 1
        )
        #expect(outcome == .failed("tccutil: Failed to reset database"))
        #expect(!outcome.succeeded)
    }

    @Test("a silent failure still produces a usable message")
    func silentFailure() {
        let outcome = AccessibilityPermission.parseReset(output: "   \n", exitCode: 70)
        #expect(outcome == .failed("tccutil failed with code 70."))
    }

    @Test("an unknown bundle identifier means nothing to clear, not an error")
    func unknownBundleIsNotAFailure() {
        // tccutil exits 64 here. Someone whose permission was already clean
        // should not be shown a red error.
        let outcome = AccessibilityPermission.parseReset(
            output: #"tccutil: No such bundle identifier "com.efoli.Clipstack": The operation couldn't be completed."#,
            exitCode: 64
        )
        #expect(outcome == .nothingToClear)
        #expect(outcome.succeeded)
    }

    @Test("tccutil reports success even when nothing was stored")
    func successWithNoPriorRecord() {
        // Verified against the real tool: it prints one success line whether or
        // not a record existed, so one line cannot be read as "there was one".
        let outcome = AccessibilityPermission.parseReset(
            output: "Successfully reset Accessibility approval status for com.efoli.Clipstack\n",
            exitCode: 0
        )
        #expect(outcome == .cleared(records: 1))
    }

    @Test("an app with no bundle identifier fails rather than resetting everything")
    func missingBundleID() {
        // A blank identifier must never reach tccutil, or it would target the
        // wrong app.
        #expect(!AccessibilityPermission.reset(bundleID: "").succeeded)
        #expect(!AccessibilityPermission.reset(bundleID: nil).succeeded)
    }
}
