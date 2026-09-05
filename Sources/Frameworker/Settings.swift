import Foundation

/// Persisted preferences, backed by UserDefaults. Posts `Settings.didChange` after every write so the
/// hotkeys and the menu can follow.
final class Settings {
    static let shared = Settings()
    static let didChange = Notification.Name("nl.zawin.frameworker.settings.didChange")
    static let defaultCustomSize = CGSize(width: 1280, height: 800)

    private let defaults = UserDefaults.standard

    private enum Key {
        static let shortcuts = "shortcuts"
        static let customWidth = "customWidth"
        static let customHeight = "customHeight"
    }

    /// Active bindings. Until the user changes anything the built-in defaults apply; after the first change
    /// the stored dictionary is authoritative, so an action missing from it is deliberately unbound.
    var shortcuts: [WindowAction: Shortcut] {
        guard let stored = defaults.dictionary(forKey: Key.shortcuts) else { return Settings.defaultShortcuts }
        var result: [WindowAction: Shortcut] = [:]
        for (key, value) in stored {
            if let action = WindowAction(rawValue: key), let shortcut = Shortcut(propertyList: value) {
                result[action] = shortcut
            }
        }
        return result
    }

    static var defaultShortcuts: [WindowAction: Shortcut] {
        var result: [WindowAction: Shortcut] = [:]
        for action in WindowAction.allCases {
            if let shortcut = action.defaultShortcut { result[action] = shortcut }
        }
        return result
    }

    var usesDefaultShortcuts: Bool { defaults.object(forKey: Key.shortcuts) == nil }

    func shortcut(for action: WindowAction) -> Shortcut? { shortcuts[action] }

    /// Assigns `shortcut` to `action`. Any other action holding the same combination is unbound, because
    /// Carbon would refuse the second registration anyway. Returns the actions that lost their shortcut.
    @discardableResult
    func setShortcut(_ shortcut: Shortcut?, for action: WindowAction) -> [WindowAction] {
        var all = shortcuts
        var displaced: [WindowAction] = []
        if let shortcut {
            for (other, existing) in all where existing == shortcut && other != action {
                all[other] = nil
                displaced.append(other)
            }
        }
        all[action] = shortcut
        save(all)
        return displaced
    }

    func resetShortcuts() {
        defaults.removeObject(forKey: Key.shortcuts)
        notify()
    }

    /// Target size for the "Vaste maat" action, in points.
    var customSize: CGSize {
        get {
            let width = defaults.double(forKey: Key.customWidth)
            let height = defaults.double(forKey: Key.customHeight)
            guard width >= 100, height >= 100 else { return Settings.defaultCustomSize }
            return CGSize(width: width, height: height)
        }
        set {
            defaults.set(newValue.width, forKey: Key.customWidth)
            defaults.set(newValue.height, forKey: Key.customHeight)
            notify()
        }
    }

    private func save(_ all: [WindowAction: Shortcut]) {
        var plist: [String: [String: Int]] = [:]
        for (action, shortcut) in all { plist[action.rawValue] = shortcut.propertyList }
        defaults.set(plist, forKey: Key.shortcuts)
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: Settings.didChange, object: self)
    }
}
