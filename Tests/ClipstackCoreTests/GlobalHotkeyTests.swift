import Carbon.HIToolbox
import Foundation
import Testing
@testable import ClipstackCore

@Suite("Hotkey combinations")
struct GlobalHotkeyTests {

    @Test("the default shortcut is Cmd+Shift+V")
    func defaultCombo() {
        let combo = GlobalHotkey.Combo.commandShiftV

        #expect(combo.keyCode == UInt32(kVK_ANSI_V))
        #expect(combo.modifiers & UInt32(cmdKey) != 0)
        #expect(combo.modifiers & UInt32(shiftKey) != 0)
        #expect(combo.displayString == "⇧⌘V")
    }

    @Test("modifiers are shown in the standard macOS order")
    func modifierOrder() {
        let combo = GlobalHotkey.Combo(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        #expect(combo.displayString == "⌃⌥⇧⌘A")
    }

    @Test("named keys use their symbol rather than a character")
    func specialKeyNames() {
        let space = GlobalHotkey.Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
        let escape = GlobalHotkey.Combo(keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey))
        let f5 = GlobalHotkey.Combo(keyCode: UInt32(kVK_F5), modifiers: UInt32(controlKey))

        #expect(space.displayString == "⌘Space")
        #expect(escape.displayString == "⌘⎋")
        #expect(f5.displayString == "⌃F5")
    }

    @Test("a combo survives being saved and restored")
    func codableRoundTrip() throws {
        let original = GlobalHotkey.Combo(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | optionKey)
        )

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(GlobalHotkey.Combo.self, from: data)

        #expect(restored == original)
    }
}

extension GlobalHotkeyTests {

    @Test("a recorded key label is preferred over the US-layout fallback")
    func recordedLabelWins() {
        // A German layout puts Z where a US layout has Y.
        let combo = GlobalHotkey.Combo(
            keyCode: UInt32(kVK_ANSI_Y),
            modifiers: UInt32(cmdKey),
            keyLabel: "Z"
        )
        #expect(combo.displayString == "⌘Z")
    }

    @Test("named keys win over a recorded label")
    func namedKeysWin() {
        // Space reports " " as its character, which would render blank.
        let combo = GlobalHotkey.Combo(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey),
            keyLabel: " "
        )
        #expect(combo.displayString == "⌘Space")
    }

    @Test("combos saved before labels existed still display correctly")
    func fallbackForLegacyCombos() throws {
        let legacy = #"{"keyCode":9,"modifiers":768}"#     // Cmd+Shift+V, no label
        let combo = try JSONDecoder().decode(
            GlobalHotkey.Combo.self,
            from: Data(legacy.utf8)
        )
        #expect(combo.displayString == "⇧⌘V")
    }

    @Test("an unknown key degrades to a readable placeholder")
    func unknownKey() {
        let combo = GlobalHotkey.Combo(keyCode: 999, modifiers: UInt32(cmdKey))
        #expect(combo.displayString == "⌘Key 999")
    }
}
