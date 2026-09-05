import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeyCenter()
    private let windows = WindowManager()
    private var settingsController: SettingsWindowController?
    private var activationObserver: NSObjectProtocol?

    /// `--snapshot <file.png>` opens the settings window, writes a PNG of it and quits. A developer aid to
    /// check the design without Screen Recording permission: a process may capture its own windows.
    private var snapshotPath: String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard snapshotPath == nil, let bundleID = Bundle.main.bundleIdentifier else { return }
        // Only one Frameworker at a time: a second copy (say, launched from the build folder) hands over
        // to the running one and quits, instead of fighting over the same hotkeys.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ownPID && !$0.isTerminated && kill($0.processIdentifier, 0) == 0 }
        if let running = others.first {
            DistributedNotificationCenter.default().postNotificationName(AppDelegate.showSettingsNotification,
                                                                         object: nil, userInfo: nil,
                                                                         deliverImmediately: true)
            running.activate(options: [])
            exit(0)
        }
    }

    private static let showSettingsNotification = Notification.Name("nl.zawin.frameworker.showSettings")
    private static let diagnoseNotification = Notification.Name("nl.zawin.frameworker.diagnose")
    private static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Frameworker.log")

    /// One line per launch in ~/Library/Logs/Frameworker.log: whether the menu bar actually placed the status
    /// item. A frame below y = 0 means macOS is hiding it. Posting the distributed notification
    /// "nl.zawin.frameworker.diagnose" adds the same line plus a survey of every running app's items.
    @objc private func logStatusItemState() { log(statusItemState) }

    @objc private func logMenuBarSurvey() { log(statusItemState + "\n" + windows.menuBarSurvey()) }

    private var statusItemState: String {
        let frame = statusItem?.button?.window?.frame ?? .zero
        return "status item frame \(NSStringFromRect(frame)) visible \(statusItem?.isVisible ?? false) " +
            "placed \(frame.minY > 0) pid \(ProcessInfo.processInfo.processIdentifier)"
    }

    private func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: AppDelegate.logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: AppDelegate.logURL)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = snapshotPath {
            runSnapshot(to: path)
            return
        }

        installStatusItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.logStatusItemState() }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(logMenuBarSurvey),
                                                            name: AppDelegate.diagnoseNotification, object: nil)
        hotKeys.handler = { [weak self] action in self?.perform(action) }
        bindHotKeys()

        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange),
                                               name: Settings.didChange, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showSettings),
                                                            name: AppDelegate.showSettingsNotification, object: nil)

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

    private func runSnapshot(to path: String) {
        installStatusItem()
        showSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            if let item = statusItem, let itemWindow = item.button?.window {
                FileHandle.standardError.write(Data("Frameworker: status item frame \(itemWindow.frame) visible \(item.isVisible)\n".utf8))
            }
            guard let window = settingsController?.window, let primary = NSScreen.screens.first else { exit(1) }
            let windowID = CGWindowID(window.windowNumber)
            var region = window.frame
            region.origin.y = primary.frame.maxY - region.maxY // Cocoa (bottom-left) to Quartz (top-left)
            let image = CGWindowListCreateImage(region, [.optionOnScreenBelowWindow, .optionIncludingWindow],
                                                windowID, [.bestResolution])
                ?? CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution])
            guard let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("Frameworker: snapshot failed\n".utf8))
                exit(1)
            }
            do {
                try png.write(to: URL(fileURLWithPath: path))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Frameworker: \(error)\n".utf8))
                exit(1)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "Frameworker"
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
            for action in WindowAction.allCases where action.group == group && action != .openSettings {
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
        if let shortcut = shortcuts[.openSettings], let equivalent = shortcut.menuKeyEquivalent {
            settings.keyEquivalent = equivalent
            settings.keyEquivalentModifierMask = shortcut.cocoaModifiers
        }
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
        perform(action)
    }

    private func perform(_ action: WindowAction) {
        if action == .openSettings { showSettings() } else { windows.perform(action) }
    }

    @objc private func showSettings() {
        if settingsController?.window == nil {
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
