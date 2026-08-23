import AppKit
import Carbon.HIToolbox
import Foundation

/// A system-wide keyboard shortcut, registered through Carbon.
///
/// Carbon is deprecated, but `RegisterEventHotKey` is still the only
/// system-wide hotkey API that needs no special permission *and* consumes the
/// keystroke, so the focused app never sees it.
/// `NSEvent.addGlobalMonitorForEvents` requires Accessibility and cannot
/// swallow the event, which would leave the underlying app reacting to
/// Cmd+Shift+V as well.
public final class GlobalHotkey {

    public struct Combo: Equatable, Codable, Sendable {
        public let keyCode: UInt32
        /// Carbon modifier mask (cmdKey, shiftKey, optionKey, controlKey).
        public let modifiers: UInt32

        /// The character this key produces on the layout in use when it was
        /// recorded. Captured up front so displaying a shortcut never needs the
        /// keyboard-layout APIs, which are unavailable outside a GUI session.
        /// Nil for combos restored from before this was stored.
        public let keyLabel: String?

        public init(keyCode: UInt32, modifiers: UInt32, keyLabel: String? = nil) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.keyLabel = keyLabel
        }

        public static let commandShiftV = Combo(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        )

        /// Builds a combo from a captured key event.
        ///
        /// Returns nil unless at least one modifier is held: a bare key would
        /// be swallowed system-wide, making that key unusable everywhere.
        public init?(event: NSEvent) {
            var carbon: UInt32 = 0
            let flags = event.modifierFlags
            if flags.contains(.command) { carbon |= UInt32(cmdKey) }
            if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
            if flags.contains(.option)  { carbon |= UInt32(optionKey) }
            if flags.contains(.control) { carbon |= UInt32(controlKey) }

            guard carbon != 0 else { return nil }

            self.keyCode = UInt32(event.keyCode)
            self.modifiers = carbon
            self.keyLabel = event.charactersIgnoringModifiers
                .map { $0.uppercased() }
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        /// Human-readable form, e.g. "⇧⌘V".
        public var displayString: String {
            var result = ""
            if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
            if modifiers & UInt32(optionKey)  != 0 { result += "⌥" }
            if modifiers & UInt32(shiftKey)   != 0 { result += "⇧" }
            if modifiers & UInt32(cmdKey)     != 0 { result += "⌘" }
            return result + keyName
        }

        /// Named keys win over the recorded character, so Space reads "Space"
        /// rather than a blank.
        var keyName: String {
            if let special = Self.specialKeyNames[Int(keyCode)] { return special }
            if let keyLabel { return keyLabel }
            if let ansi = Self.ansiKeyNames[Int(keyCode)] { return ansi }
            return "Key \(keyCode)"
        }

        private static let specialKeyNames: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]

        /// US-layout fallback, used only for combos saved before `keyLabel`
        /// existed. Anything recorded now carries its own label.
        private static let ansiKeyNames: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
            kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
            kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
            kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
        ]
    }

    /// Four-char code 'MCLP', used to ignore hotkey events from other apps.
    private static let signature: OSType = 0x4D43_4C50

    // The Carbon callback is a bare C function pointer and cannot capture
    // context, so handlers are looked up by hotkey id. All access happens on
    // the main thread, where Carbon dispatches events.
    private static var registry: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private var ref: EventHotKeyRef?

    /// Returns nil if the combination is already claimed by another process.
    public init?(combo: Combo, handler: @escaping () -> Void) {
        Self.installDispatcherIfNeeded()

        id = Self.nextID
        Self.nextID += 1

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var created: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &created
        )

        guard status == noErr, let created else { return nil }
        ref = created
        Self.registry[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.registry[id] = nil
    }

    private static func installDispatcherIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr,
                      hotKeyID.signature == GlobalHotkey.signature,
                      let handler = GlobalHotkey.registry[hotKeyID.id]
                else { return OSStatus(eventNotHandledErr) }

                handler()
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}
