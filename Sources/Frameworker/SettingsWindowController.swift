import AppKit

/// Dark, translucent settings window: shortcut recorders per group, the fixed custom size, and
/// launch at login. Built in plain AppKit so it costs nothing while it is closed.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onRecordingChange: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    /// Actions whose shortcut the system refused; their pills turn orange.
    var unavailableActions: Set<WindowAction> = [] { didSet { refreshRecorders() } }

    private let settings = Settings.shared
    private var recorders: [WindowAction: ShortcutRecorderView] = [:]
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let loginCheckbox = NSButton(checkboxWithTitle: "Start Frameworker automatisch bij inloggen",
                                         target: nil, action: nil)
    private var accessibilityCard: NSView?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Frameworker"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
    }

    required init?(coder: NSCoder) { fatalError("Storyboards are not used") }

    func show() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
    func windowDidBecomeKey(_ notification: Notification) { refresh() }

    // MARK: Building the view hierarchy

    private func buildContent(in window: NSWindow) {
        guard let content = window.contentView else { return }

        let backdrop = NSVisualEffectView()
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        pin(backdrop, to: content)

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 0.45).cgColor
        pin(tint, to: content)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        pin(scroll, to: content)

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.widthAnchor.constraint(equalTo: clip.widthAnchor),
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 48, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])

        stack.addArrangedSubview(header())
        let notice = accessibilityNotice()
        accessibilityCard = notice
        stack.addArrangedSubview(notice)
        for group in WindowAction.Group.allCases {
            stack.addArrangedSubview(GlassCard(title: group.title, content: shortcutGrid(for: group)))
        }
        stack.addArrangedSubview(GlassCard(title: "Vaste maat", content: sizeRow()))
        stack.addArrangedSubview(GlassCard(title: "Algemeen", content: generalRows()))
        stack.addArrangedSubview(footer())
    }

    private func pin(_ view: NSView, to parent: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            view.topAnchor.constraint(equalTo: parent.topAnchor),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    private func header() -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 30, weight: .medium))
        icon.contentTintColor = .labelColor
        let title = label("Frameworker", font: .systemFont(ofSize: 24, weight: .bold), color: .labelColor)
        let subtitle = label("Klik op een veld en druk de nieuwe toetscombinatie in. Backspace maakt een veld leeg.",
                             font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 2
        subtitle.preferredMaxLayoutWidth = 440
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        return row
    }

    private func accessibilityNotice() -> NSView {
        let text = label("Frameworker mag nog geen vensters verplaatsen. Zet het aan onder Privacy en beveiliging, Toegankelijkheid.",
                         font: .systemFont(ofSize: 13), color: .labelColor)
        text.lineBreakMode = .byWordWrapping
        text.maximumNumberOfLines = 3
        text.preferredMaxLayoutWidth = 300
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let button = NSButton(title: "Systeeminstellingen openen", target: self, action: #selector(openAccessibilitySettings))
        button.bezelStyle = .rounded
        let row = NSStackView(views: [text, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return GlassCard(title: "Toegang nodig", content: row, tint: NSColor.systemOrange.withAlphaComponent(0.28))
    }

    private func shortcutGrid(for group: WindowAction.Group) -> NSView {
        let grid = NSGridView()
        grid.rowSpacing = 8
        grid.columnSpacing = 16
        grid.yPlacement = .center
        for action in WindowAction.allCases where action.group == group {
            let name = label(action.title, font: .systemFont(ofSize: 13), color: .labelColor)
            let recorder = ShortcutRecorderView()
            recorder.onChange = { [weak self] shortcut in
                guard let self else { return }
                self.settings.setShortcut(shortcut, for: action)
                self.refreshRecorders()
            }
            recorder.onRecordingChange = { [weak self] recording in self?.onRecordingChange?(recording) }
            recorders[action] = recorder
            grid.addRow(with: [name, recorder])
        }
        grid.column(at: 0).width = 240
        grid.column(at: 1).xPlacement = .leading
        return grid
    }

    private func sizeRow() -> NSView {
        configureSizeField(widthField)
        configureSizeField(heightField)
        let name = label("Breedte en hoogte", font: .systemFont(ofSize: 13), color: .labelColor)
        let times = label("×", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        let unit = label("px, gecentreerd op het scherm", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        let row = NSStackView(views: [name, widthField, times, heightField, unit])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.setCustomSpacing(16, after: name)
        return row
    }

    private func configureSizeField(_ field: NSTextField) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 100
        formatter.maximum = 10000
        formatter.allowsFloats = false
        field.formatter = formatter
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.bezelStyle = .roundedBezel
        field.target = self
        field.action = #selector(sizeChanged)
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 76).isActive = true
    }

    private func generalRows() -> NSView {
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        loginCheckbox.font = .systemFont(ofSize: 13)
        return loginCheckbox
    }

    private func footer() -> NSView {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let versionLabel = label("Frameworker \(version)", font: .systemFont(ofSize: 12), color: .tertiaryLabelColor)
        let reset = NSButton(title: "Standaardsneltoetsen herstellen", target: self, action: #selector(resetShortcuts))
        reset.bezelStyle = .rounded
        let row = NSStackView(views: [versionLabel, reset])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .equalSpacing
        return row
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        return field
    }

    // MARK: State

    private func refresh() {
        refreshRecorders()
        widthField.integerValue = Int(settings.customSize.width)
        heightField.integerValue = Int(settings.customSize.height)
        loginCheckbox.state = LoginItem.isEnabled ? .on : .off
        accessibilityCard?.isHidden = WindowManager.isTrusted
    }

    private func refreshRecorders() {
        let all = settings.shortcuts
        for (action, recorder) in recorders {
            recorder.shortcut = all[action]
            recorder.isUnavailable = unavailableActions.contains(action)
        }
    }

    @objc private func sizeChanged() {
        let width = widthField.integerValue
        let height = heightField.integerValue
        guard width >= 100, height >= 100 else {
            refresh()
            return
        }
        let size = CGSize(width: width, height: height)
        if size != settings.customSize { settings.customSize = size }
    }

    @objc private func toggleLogin() {
        do {
            try LoginItem.setEnabled(loginCheckbox.state == .on)
        } catch {
            NSLog("Frameworker: login item change failed: \(error)")
            loginCheckbox.state = LoginItem.isEnabled ? .on : .off
        }
    }

    @objc private func resetShortcuts() {
        settings.resetShortcuts()
        refreshRecorders()
    }

    @objc private func openAccessibilitySettings() {
        WindowManager.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// NSScrollView document views are bottom-up by default; flipping keeps the content at the top.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Section container. On macOS 26 it is real Liquid Glass (NSGlassEffectView); on older systems a
/// translucent rounded panel that reads the same way.
final class GlassCard: NSView {
    init(title: String, content: NSView, tint: NSColor? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "")
        heading.attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.8,
        ])

        let inner = NSStackView(views: [heading, content])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 12
        inner.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 16, right: 18)
        inner.translatesAutoresizingMaskIntoConstraints = false

        let surface: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 18
            glass.style = .regular
            glass.tintColor = tint ?? NSColor(calibratedWhite: 0, alpha: 0.35)
            glass.contentView = inner
            surface = glass
        } else {
            let panel = NSView()
            panel.wantsLayer = true
            panel.layer?.cornerRadius = 18
            panel.layer?.cornerCurve = .continuous
            panel.layer?.backgroundColor = (tint ?? NSColor.white.withAlphaComponent(0.07)).cgColor
            panel.layer?.borderWidth = 1
            panel.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            panel.addSubview(inner)
            surface = panel
        }
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            inner.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            inner.topAnchor.constraint(equalTo: surface.topAnchor),
            inner.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Storyboards are not used") }
}
