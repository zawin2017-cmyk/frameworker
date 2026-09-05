import Carbon
import Foundation

/// Every window operation Frameworker can perform. The raw value is the key used in UserDefaults,
/// so renaming a case would silently drop a user's custom shortcut for it.
enum WindowAction: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize, almostMaximize, center, customSize
    case smaller, larger
    case restore, nextDisplay, previousDisplay

    enum Group: CaseIterable {
        case halves, quarters, thirds, size, other

        var title: String {
            switch self {
            case .halves: return "Helften"
            case .quarters: return "Kwarten"
            case .thirds: return "Derden"
            case .size: return "Formaat"
            case .other: return "Overig"
            }
        }
    }

    var group: Group {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return .halves
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return .quarters
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds: return .thirds
        case .maximize, .almostMaximize, .center, .customSize, .smaller, .larger: return .size
        case .restore, .nextDisplay, .previousDisplay: return .other
        }
    }

    /// Dutch label used in the menu and the settings window.
    var title: String {
        switch self {
        case .leftHalf: return "Linkerhelft"
        case .rightHalf: return "Rechterhelft"
        case .topHalf: return "Bovenste helft"
        case .bottomHalf: return "Onderste helft"
        case .topLeft: return "Linksboven"
        case .topRight: return "Rechtsboven"
        case .bottomLeft: return "Linksonder"
        case .bottomRight: return "Rechtsonder"
        case .firstThird: return "Eerste derde"
        case .centerThird: return "Middelste derde"
        case .lastThird: return "Laatste derde"
        case .firstTwoThirds: return "Eerste tweederde"
        case .lastTwoThirds: return "Laatste tweederde"
        case .maximize: return "Maximaliseren"
        case .almostMaximize: return "Bijna maximaliseren"
        case .center: return "Centreren"
        case .customSize: return "Vaste maat"
        case .smaller: return "Kleiner"
        case .larger: return "Groter"
        case .restore: return "Herstellen"
        case .nextDisplay: return "Naar volgend scherm"
        case .previousDisplay: return "Naar vorig scherm"
        }
    }

    /// Built-in bindings, deliberately the same as Rectangle's so muscle memory carries over.
    var defaultShortcut: Shortcut? {
        let base = Shortcut.controlOption
        switch self {
        case .leftHalf: return Shortcut(keyCode: kVK_LeftArrow, modifiers: base)
        case .rightHalf: return Shortcut(keyCode: kVK_RightArrow, modifiers: base)
        case .topHalf: return Shortcut(keyCode: kVK_UpArrow, modifiers: base)
        case .bottomHalf: return Shortcut(keyCode: kVK_DownArrow, modifiers: base)
        case .topLeft: return Shortcut(keyCode: kVK_ANSI_U, modifiers: base)
        case .topRight: return Shortcut(keyCode: kVK_ANSI_I, modifiers: base)
        case .bottomLeft: return Shortcut(keyCode: kVK_ANSI_J, modifiers: base)
        case .bottomRight: return Shortcut(keyCode: kVK_ANSI_K, modifiers: base)
        case .firstThird: return Shortcut(keyCode: kVK_ANSI_D, modifiers: base)
        case .centerThird: return Shortcut(keyCode: kVK_ANSI_F, modifiers: base)
        case .lastThird: return Shortcut(keyCode: kVK_ANSI_G, modifiers: base)
        case .firstTwoThirds: return Shortcut(keyCode: kVK_ANSI_E, modifiers: base)
        case .lastTwoThirds: return Shortcut(keyCode: kVK_ANSI_T, modifiers: base)
        case .maximize: return Shortcut(keyCode: kVK_Return, modifiers: base)
        case .almostMaximize: return nil
        case .center: return Shortcut(keyCode: kVK_ANSI_C, modifiers: base)
        case .customSize: return Shortcut(keyCode: kVK_ANSI_V, modifiers: base)
        case .smaller: return Shortcut(keyCode: kVK_ANSI_Minus, modifiers: base)
        case .larger: return Shortcut(keyCode: kVK_ANSI_Equal, modifiers: base)
        case .restore: return Shortcut(keyCode: kVK_Delete, modifiers: base)
        case .nextDisplay: return Shortcut(keyCode: kVK_RightArrow, modifiers: Shortcut.controlOptionCommand)
        case .previousDisplay: return Shortcut(keyCode: kVK_LeftArrow, modifiers: Shortcut.controlOptionCommand)
        }
    }

    /// Stable numeric id, used for Carbon hotkey ids and menu item tags.
    var index: Int { WindowAction.allCases.firstIndex(of: self)! }

    static func from(index: Int) -> WindowAction? {
        allCases.indices.contains(index) ? allCases[index] : nil
    }
}
