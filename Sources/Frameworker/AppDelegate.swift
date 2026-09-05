import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeyCenter()
    private let windows = WindowManager()
    private var settingsController: SettingsWindowController?
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        hotKeys.handler = { [weak self] action in self?.windows.perform(action) }
        bindHotKeys()

        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange),
                                               name: Settings.didChange, object: nil)

        // Track the app the user is really working in, so menu clicks and the settings window (which make
        // Frameworker itself frontmost) still act on the right window.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != ownPID {
            windows.lastActiveApp = frontmost
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ownPID else { return }
            self?.windows.lastActiveApp = app
        }

        if !WindowManager.isTrusted { WindowManager.requestTrust() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Frameworker")?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
            button.image?.isTemplate = true
            button.toolTip = "Frameworker"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    private func bindHotKeys() {
        hotKeys.bind(Settings.shared.shortcuts)
        settingsController?.unavailableActions = hotKeys.failed
    }

    @objc private func settingsDidChange() { bindHotKeys() }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !WindowManager.isTrusted {
            menu.addItem(item("Toegankelijkheid inschakelen…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        let shortcuts = Settings.shared.shortcuts
        for group in WindowAction.Group.allCases {
            menu.addItem(NSMenuItem.sectionHeader(title: group.title))
            for action in WindowAction.allCases where action.group == group {
                let entry = item(action.title, #selector(performMenuAction(_:)))
                entry.tag = action.index
                if let shortcut = shortcuts[action] {
                    if let equivalent = shortcut.menuKeyEquivalent {
                        entry.keyEquivalent = equivalent
                        entry.keyEquivalentModifierMask = shortcut.cocoaModifiers
                    } else {
                        entry.title = "\(action.title)  \(shortcut.displayString)"
                    }
                }
                if hotKeys.failed.contains(action) {
                    entry.title += "  ⚠︎"
                    entry.toolTip = "Deze toetscombinatie is al in gebruik door een andere app."
                }
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        let settings = item("Instellingen…", #selector(showSettings))
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = .command
        menu.addItem(settings)
        let login = item("Start bij inloggen", #selector(toggleLoginItem))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Over Frameworker", #selector(showAbout)))
        menu.addItem(NSMenuItem(title: "Frameworker stoppen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        return entry
    }

    // MARK: Actions

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let action = WindowAction.from(index: sender.tag) else { return }
        windows.perform(action)
    }

    @objc private func showSettings() {
        if settingsController == nil {
            let controller = SettingsWindowController()
            controller.onRecordingChange = { [weak self] recording in
                if recording { self?.hotKeys.pause() } else { self?.hotKeys.resume() }
            }
            controller.onClose = { [weak self] in
                DispatchQueue.main.async { self?.settingsController = nil }
            }
            settingsController = controller
        }
        settingsController?.unavailableActions = hotKeys.failed
        settingsController?.show()
    }

    @objc private func toggleLoginItem() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            NSLog("Frameworker: login item change failed: \(error)")
        }
    }

    @objc private func openAccessibilitySettings() {
        WindowManager.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
