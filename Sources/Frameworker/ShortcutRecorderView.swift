import AppKit

/// Pill-shaped control that records one key combination. Click to start recording, press a combination
/// to store it, Escape cancels, Backspace clears, and so does the × that appears on hover. While
/// recording, a local event monitor swallows every key event so the combination cannot reach menus
/// or text fields.
final class ShortcutRecorderView: NSView {
    var shortcut: Shortcut? {
        didSet {
            toolTip = shortcut?.displayString
            needsDisplay = true
        }
    }

    /// Marks a combination the system refused to register because another app owns it.
    var isUnavailable = false { didSet { needsDisplay = true } }

    var onChange: ((Shortcut?) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private(set) var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            onRecordingChange?(isRecording)
            needsDisplay = true
        }
    }

    private var heldModifiers: UInt32 = 0
    private var monitor: Any?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { needsDisplay = true } }

    /// Room around the pill so the recording glow is not clipped.
    private let padding: CGFloat = 3
    private let clearZoneWidth: CGFloat = 26

    override init(frame: NSRect) {
        super.init(frame: frame)
        focusRingType = .none // the recording glow is the focus indicator
    }

    required init?(coder: NSCoder) { fatalError("Storyboards are not used") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 162, height: 32) }
    override var focusRingMaskBounds: NSRect { pillRect }

    private var pillRect: NSRect { bounds.insetBy(dx: padding, dy: padding) }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        if shortcut != nil, location.x > pillRect.maxX - clearZoneWidth {
            shortcut = nil
            onChange?(nil)
            return
        }
        window?.makeFirstResponder(self)
        startRecording()
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { stopRecording() }
        return super.resignFirstResponder()
    }

    // MARK: Recording

    private func startRecording() {
        heldModifiers = 0
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        heldModifiers = 0
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        switch event.type {
        case .flagsChanged:
            heldModifiers = Shortcut.carbonModifiers(from: flags)
            needsDisplay = true
        case .keyDown:
            if event.keyCode == 53, flags.isEmpty { // Escape
                stopRecording()
                return
            }
            if event.keyCode == 51, flags.isEmpty { // Backspace
                shortcut = nil
                stopRecording()
                onChange?(nil)
                return
            }
            let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: Shortcut.carbonModifiers(from: flags))
            guard candidate.isUsable else {
                NSSound.beep()
                return
            }
            shortcut = candidate
            stopRecording()
            onChange?(candidate)
        default:
            break
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let rect = pillRect
        let radius = rect.height / 2
        let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)

        let fill: NSColor
        let rim: NSColor
        if isRecording {
            fill = NSColor.controlAccentColor.withAlphaComponent(0.26)
            rim = NSColor.controlAccentColor.withAlphaComponent(0.95)
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.55)
            glow.shadowBlurRadius = 6
            glow.set()
            fill.setFill()
            pill.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else if isUnavailable {
            fill = NSColor.systemOrange.withAlphaComponent(0.18)
            rim = NSColor.systemOrange.withAlphaComponent(0.65)
            fill.setFill()
            pill.fill()
        } else if shortcut == nil {
            fill = NSColor.white.withAlphaComponent(isHovered ? 0.08 : 0.04)
            rim = NSColor.white.withAlphaComponent(0.10)
            fill.setFill()
            pill.fill()
        } else {
            fill = NSColor.white.withAlphaComponent(isHovered ? 0.16 : 0.10)
            rim = NSColor.white.withAlphaComponent(0.20)
            fill.setFill()
            pill.fill()
        }

        // A faint highlight along the top edge gives the pill its glass feel.
        NSGraphicsContext.saveGraphicsState()
        pill.addClip()
        NSGradient(starting: NSColor.white.withAlphaComponent(0), ending: NSColor.white.withAlphaComponent(0.12))?
            .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        rim.setStroke()
        pill.lineWidth = 1
        pill.stroke()

        let text: String
        let color: NSColor
        if isRecording {
            text = heldModifiers != 0 ? Shortcut.symbols(for: heldModifiers) + "…" : "Toets indrukken…"
            color = .labelColor
        } else if let shortcut {
            text = shortcut.displayString
            color = .labelColor
        } else {
            text = "Geen"
            color = .tertiaryLabelColor
        }

        let showsClear = shortcut != nil && !isRecording && isHovered
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let availableWidth = rect.width - (showsClear ? clearZoneWidth : 0)
        let origin = NSPoint(x: rect.minX + ((availableWidth - size.width) / 2).rounded(),
                             y: rect.minY + ((rect.height - size.height) / 2).rounded())
        (text as NSString).draw(at: origin, withAttributes: attributes)

        if showsClear {
            let glyphAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let glyph = "✕" as NSString
            let glyphSize = glyph.size(withAttributes: glyphAttributes)
            glyph.draw(at: NSPoint(x: rect.maxX - clearZoneWidth / 2 - glyphSize.width / 2 - 2,
                                   y: rect.minY + ((rect.height - glyphSize.height) / 2).rounded()),
                       withAttributes: glyphAttributes)
        }
    }
}
