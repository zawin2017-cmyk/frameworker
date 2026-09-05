import AppKit

/// Pill-shaped control that records one key combination. Click to start recording, press a combination
/// to store it, Escape cancels, Backspace clears, and so does the × on the right. While recording, a
/// local event monitor swallows every key event so the combination cannot reach menus or text fields.
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
    private let clearZoneWidth: CGFloat = 26

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 168, height: 28) }
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
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
        if shortcut != nil, location.x > bounds.width - clearZoneWidth {
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
        let radius = bounds.height / 2
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)

        let fill: NSColor
        let stroke: NSColor
        if isRecording {
            fill = NSColor.controlAccentColor.withAlphaComponent(0.22)
            stroke = NSColor.controlAccentColor.withAlphaComponent(0.9)
        } else if isUnavailable {
            fill = NSColor.systemOrange.withAlphaComponent(0.18)
            stroke = NSColor.systemOrange.withAlphaComponent(0.6)
        } else {
            fill = NSColor.white.withAlphaComponent(isHovered ? 0.14 : 0.08)
            stroke = NSColor.white.withAlphaComponent(0.16)
        }
        fill.setFill()
        pill.fill()

        // A faint highlight along the top edge gives the pill its glass feel.
        NSGraphicsContext.saveGraphicsState()
        pill.addClip()
        NSGradient(starting: NSColor.white.withAlphaComponent(0), ending: NSColor.white.withAlphaComponent(0.10))?
            .draw(in: NSRect(x: 0, y: bounds.height / 2, width: bounds.width, height: bounds.height / 2), angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        stroke.setStroke()
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

        let showsClear = shortcut != nil && !isRecording
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let availableWidth = bounds.width - (showsClear ? clearZoneWidth : 0)
        let origin = NSPoint(x: ((availableWidth - size.width) / 2).rounded(),
                             y: ((bounds.height - size.height) / 2).rounded())
        (text as NSString).draw(at: origin, withAttributes: attributes)

        if showsClear {
            let glyphAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(isHovered ? 1 : 0.6),
            ]
            let glyph = "✕" as NSString
            let glyphSize = glyph.size(withAttributes: glyphAttributes)
            glyph.draw(at: NSPoint(x: bounds.width - clearZoneWidth / 2 - glyphSize.width / 2 - 2,
                                   y: ((bounds.height - glyphSize.height) / 2).rounded()),
                       withAttributes: glyphAttributes)
        }
    }
}
