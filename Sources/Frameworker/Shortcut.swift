import AppKit
import Carbon

/// A key combination: a layout-independent virtual key code plus Carbon modifier flags.
struct Shortcut: Equatable, Hashable {
    let keyCode: UInt32
    /// Carbon modifier mask (controlKey, optionKey, shiftKey, cmdKey), as RegisterEventHotKey expects it.
    let modifiers: UInt32

    static let controlOption = UInt32(controlKey | optionKey)
    static let controlOptionCommand = UInt32(controlKey | optionKey | cmdKey)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(keyCode: Int, modifiers: UInt32) {
        self.init(keyCode: UInt32(keyCode), modifiers: modifiers)
    }

    // MARK: Modifiers

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// Apple's canonical ordering: control, option, shift, command.
    static func symbols(for modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    var modifierSymbols: String { Shortcut.symbols(for: modifiers) }
    var keyName: String { KeyNames.name(for: keyCode) }
    var displayString: String { modifierSymbols + keyName }

    /// A combination without modifiers would hijack ordinary typing; only bare function keys are allowed.
    var isUsable: Bool { modifiers != 0 || KeyNames.functionKeyCodes.contains(keyCode) }

    /// String NSMenuItem needs to show this key next to a menu title, or nil if it has no representation.
    var menuKeyEquivalent: String? { KeyNames.keyEquivalent(for: keyCode) }

    // MARK: Persistence

    var propertyList: [String: Int] {
        ["keyCode": Int(keyCode), "modifiers": Int(modifiers)]
    }

    init?(propertyList: Any) {
        guard let dictionary = propertyList as? [String: Int],
              let keyCode = dictionary["keyCode"], keyCode >= 0,
              let modifiers = dictionary["modifiers"], modifiers >= 0 else { return nil }
        self.init(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
    }
}

/// Human-readable names for virtual key codes. Special keys come from a table; everything else is
/// translated through the current keyboard layout so a Dutch or German layout shows the right glyph.
enum KeyNames {
    static let functionKeyCodes: Set<UInt32> = Set([
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ].map(UInt32.init))

    private struct Special {
        let name: String
        let equivalent: String
    }

    private static func functionKey(_ scalar: Int) -> String {
        String(Character(Unicode.Scalar(UInt32(scalar))!))
    }

    private static let special: [UInt32: Special] = {
        var table: [UInt32: Special] = [
            UInt32(kVK_LeftArrow): Special(name: "←", equivalent: functionKey(NSLeftArrowFunctionKey)),
            UInt32(kVK_RightArrow): Special(name: "→", equivalent: functionKey(NSRightArrowFunctionKey)),
            UInt32(kVK_UpArrow): Special(name: "↑", equivalent: functionKey(NSUpArrowFunctionKey)),
            UInt32(kVK_DownArrow): Special(name: "↓", equivalent: functionKey(NSDownArrowFunctionKey)),
            UInt32(kVK_Return): Special(name: "↩", equivalent: "\r"),
            UInt32(kVK_ANSI_KeypadEnter): Special(name: "⌤", equivalent: "\u{3}"),
            UInt32(kVK_Tab): Special(name: "⇥", equivalent: "\t"),
            UInt32(kVK_Space): Special(name: "␣", equivalent: " "),
            UInt32(kVK_Delete): Special(name: "⌫", equivalent: "\u{8}"),
            UInt32(kVK_ForwardDelete): Special(name: "⌦", equivalent: functionKey(NSDeleteFunctionKey)),
            UInt32(kVK_Escape): Special(name: "⎋", equivalent: "\u{1B}"),
            UInt32(kVK_Home): Special(name: "↖", equivalent: functionKey(NSHomeFunctionKey)),
            UInt32(kVK_End): Special(name: "↘", equivalent: functionKey(NSEndFunctionKey)),
            UInt32(kVK_PageUp): Special(name: "⇞", equivalent: functionKey(NSPageUpFunctionKey)),
            UInt32(kVK_PageDown): Special(name: "⇟", equivalent: functionKey(NSPageDownFunctionKey)),
        ]
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (offset, code) in fKeys.enumerated() {
            table[UInt32(code)] = Special(name: "F\(offset + 1)", equivalent: functionKey(NSF1FunctionKey + offset))
        }
        return table
    }()

    static func name(for keyCode: UInt32) -> String {
        if let entry = special[keyCode] { return entry.name }
        return translate(keyCode)?.uppercased() ?? "Toets \(keyCode)"
    }

    static func keyEquivalent(for keyCode: UInt32) -> String? {
        if let entry = special[keyCode] { return entry.equivalent }
        guard let text = translate(keyCode), text.count == 1 else { return nil }
        return text.lowercased()
    }

    /// Asks the active keyboard layout which character sits on `keyCode` when no modifiers are held.
    private static func translate(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, 4, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
