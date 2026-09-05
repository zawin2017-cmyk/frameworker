import AppKit

/// Dark, translucent settings window: a fixed header, then glass cards with the shortcut recorders per
/// group, the fixed custom size, and launch at login. Plain AppKit, so it costs nothing while closed.
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
    private let hintLabel = NSTextField(labelWithString: "")
    private var hintTimer: DispatchWorkItem?
    private var accessibilityCard: NSView?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Frameworker"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 480)
        window.autorecalculatesKeyViewLoop = false // no pill gets focus until it is clicked
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
        window?.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
    func windowDidBecomeKey(_ notification: Notification) { refresh() }

    // MARK: Building the view hierarchy

    private func buildContent(in window: NSWindow) {
        guard let content = window.contentView else { return }

        // Translucent dark base that lets the desktop through, with a moody gradient on top so the glass
        // cards have something to refract even when the window sits over a plain dark app.
        let backdrop = NSVisualEffectView()
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        pin(backdrop, to: content)
        pin(AuroraView(), to: content)

        let header = header()
        header.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(header)

        let separator = hairline()
        content.addSubview(separator)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 40),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

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
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])

        let notice = accessibilityNotice()
        accessibilityCard = notice
        Self.addFullWidth(notice, to: stack)
        for group in WindowAction.Group.allCases {
            Self.addFullWidth(GlassCard(title: group.title, content: shortcutRows(for: group)), to: stack)
        }
        Self.addFullWidth(GlassCard(title: "Vaste maat", content: sizeRow()), to: stack)
        Self.addFullWidth(GlassCard(title: "Algemeen", content: generalRows()), to: stack)
        Self.addFullWidth(footer(), to: stack)
    }

    /// NSStackView applies its `.width` alignment at priority 250 only, which loses against any view that
    /// hugs its content (NSGlassEffectView does). Pinning both edges at required priority settles it.
    private static func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: stack.edgeInsets.left),
            view.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -stack.edgeInsets.right),
        ])
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

    private func hairline() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func header() -> NSView {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 60).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 60).isActive = true

        let title = label("Frameworker", font: .systemFont(ofSize: 26, weight: .semibold), color: .labelColor)
        let subtitle = label("Klik op een veld en druk de nieuwe toetscombinatie in. Escape annuleert, Backspace maakt leeg.",
                             font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.maximumNumberOfLines = 2
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        hintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hintLabel.textColor = .systemYellow
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 2
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hintLabel.isHidden = true

        let text = NSStackView(views: [title, subtitle, hintLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.setCustomSpacing(6, after: subtitle)

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return row
    }

    private func accessibilityNotice() -> NSView {
        let text = label("Frameworker mag nog geen vensters verplaatsen. Zet het aan onder Privacy en beveiliging, Toegankelijkheid.",
                         font: .systemFont(ofSize: 13), color: .labelColor)
        text.lineBreakMode = .byWordWrapping
        text.maximumNumberOfLines = 3
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let button = NSButton(title: "Systeeminstellingen openen", target: self, action: #selector(openAccessibilitySettings))
        button.bezelStyle = .rounded
        let row = NSStackView(views: [text, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return GlassCard(title: "Toegang nodig", content: row, tint: NSColor.systemOrange.withAlphaComponent(0.30))
    }

    /// One row per action: the name on the left, the recorder pill flush right, hairlines in between.
    private func shortcutRows(for group: WindowAction.Group) -> NSView {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 0
        let actions = WindowAction.allCases.filter { $0.group == group }
        for (index, action) in actions.enumerated() {
            let name = label(action.title, font: .systemFont(ofSize: 13), color: .labelColor)
            name.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let recorder = ShortcutRecorderView()
            recorder.onChange = { [weak self] shortcut in
                guard let self else { return }
                let displaced = self.settings.setShortcut(shortcut, for: action)
                self.refreshRecorders()
                if let shortcut, !displaced.isEmpty {
                    let names = displaced.map(\.title).joined(separator: ", ")
                    self.showHint("\(shortcut.displayString) stond bij \(names) en is daar losgemaakt.")
                }
            }
            recorder.onRecordingChange = { [weak self] recording in self?.onRecordingChange?(recording) }
            recorders[action] = recorder

            let row = NSStackView(views: [name, recorder])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.translatesAutoresizingMaskIntoConstraints = false
            row.heightAnchor.constraint(equalToConstant: 38).isActive = true
            Self.addFullWidth(row, to: rows)
            if index < actions.count - 1 { Self.addFullWidth(hairline(), to: rows) }
        }
        return rows
    }

    private func sizeRow() -> NSView {
        configureSizeField(widthField)
        configureSizeField(heightField)
        let name = label("Breedte en hoogte", font: .systemFont(ofSize: 13), color: .labelColor)
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let times = label("×", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        let unit = label("px", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        let fields = NSStackView(views: [widthField, times, heightField, unit])
        fields.orientation = .horizontal
        fields.alignment = .centerY
        fields.spacing = 8
        let row = NSStackView(views: [name, fields])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 38).isActive = true
        let note = label("Het venster wordt op deze maat gezet en gecentreerd op zijn scherm.",
                         font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .width
        column.spacing = 4
        Self.addFullWidth(row, to: column)
        Self.addFullWidth(note, to: column)
        return column
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

    private func showHint(_ text: String) {
        hintTimer?.cancel()
        hintLabel.stringValue = text
        hintLabel.isHidden = false
        let hide = DispatchWorkItem { [weak self] in self?.hintLabel.isHidden = true }
        hintTimer = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: hide)
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

/// Static, layer-only gradient: a deep navy base with two soft colour blooms. Nothing animates, so it is
/// composited once and costs nothing afterwards.
final class AuroraView: NSView {
    private let base = CAGradientLayer()
    private let indigo = CAGradientLayer()
    private let teal = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true

        base.colors = [
            NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.19, alpha: 0.62).cgColor,
            NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.07, alpha: 0.80).cgColor,
        ]
        base.startPoint = CGPoint(x: 0.5, y: 1)
        base.endPoint = CGPoint(x: 0.5, y: 0)

        for (bloom, color) in [(indigo, NSColor(calibratedRed: 0.36, green: 0.36, blue: 0.95, alpha: 0.55)),
                               (teal, NSColor(calibratedRed: 0.12, green: 0.60, blue: 0.70, alpha: 0.42))] {
            bloom.type = .radial
            bloom.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
            bloom.locations = [0, 1]
            bloom.startPoint = CGPoint(x: 0.5, y: 0.5)
            bloom.endPoint = CGPoint(x: 1, y: 1)
        }
        layer?.addSublayer(base)
        layer?.addSublayer(indigo)
        layer?.addSublayer(teal)
    }

    required init?(coder: NSCoder) { fatalError("Storyboards are not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        base.frame = bounds
        let w = bounds.width, h = bounds.height
        indigo.frame = CGRect(x: -0.35 * w, y: h - 0.55 * h, width: 1.1 * w, height: 1.1 * w)
        teal.frame = CGRect(x: 0.35 * w, y: -0.55 * w, width: 1.1 * w, height: 1.1 * w)
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }
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
            .kern: 0.9,
        ])

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .width
        inner.spacing = 6
        inner.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 10, right: 18)
        inner.translatesAutoresizingMaskIntoConstraints = false
        for view in [heading, content] {
            inner.addArrangedSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: inner.edgeInsets.left),
                view.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -inner.edgeInsets.right),
            ])
        }

        let surface: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 20
            glass.style = .regular
            glass.tintColor = tint
            glass.contentView = inner
            surface = glass
        } else {
            let panel = NSView()
            panel.wantsLayer = true
            panel.layer?.cornerRadius = 20
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
