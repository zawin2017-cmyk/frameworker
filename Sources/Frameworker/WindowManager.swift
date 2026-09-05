import AppKit
import ApplicationServices

/// Moves and resizes other apps' windows through the Accessibility API.
final class WindowManager {
    /// The app that was frontmost before Frameworker itself became active (menu click, settings window).
    var lastActiveApp: NSRunningApplication?

    private var restoreFrames: [WindowKey: CGRect] = [:]
    private var restoreOrder: [WindowKey] = []
    private let restoreLimit = 64

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to System Settings > Privacy > Accessibility.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func perform(_ action: WindowAction) {
        guard WindowManager.isTrusted,
              let window = focusedWindow(),
              !isFullScreen(window),
              let frame = frame(of: window) else { return }

        let screens = ScreenGeometry.visibleFrames()
        guard let index = Layout.screenIndex(containing: frame, in: screens) else { return }
        let visible = screens[index]
        let key = WindowKey(window)

        switch action {
        case .restore:
            guard let saved = restoreFrames[key] else { return }
            forget(key)
            set(frame: saved, for: window)
        case .nextDisplay, .previousDisplay:
            guard screens.count > 1 else { return }
            let offset = action == .nextDisplay ? 1 : screens.count - 1
            let target = screens[(index + offset) % screens.count]
            remember(frame, for: key)
            set(frame: Layout.translated(frame, from: visible, to: target), for: window)
        case .openSettings:
            return
        default:
            let step = Layout.nextStep(for: action, window: frame, visible: visible, customSize: Settings.shared.customSize)
            guard let target = Layout.frame(for: step, window: frame, visible: visible,
                                            customSize: Settings.shared.customSize) else { return }
            remember(frame, for: key)
            set(frame: target, for: window)
        }
    }

    // MARK: Diagnostics

    /// Where every running app's status items ended up, as seen through Accessibility. A frame at the top
    /// of a screen means the menu bar placed the item; anything else means it is hidden.
    func menuBarSurvey() -> String {
        guard WindowManager.isTrusted else { return "no accessibility trust" }
        var lines = ["screens: " + NSScreen.screens.map { NSStringFromRect($0.frame) }.joined(separator: " ")]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            var value: CFTypeRef?
            let element = AXUIElementCreateApplication(app.processIdentifier)
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
            var childrenValue: CFTypeRef?
            AXUIElementCopyAttributeValue(unsafeBitCast(value, to: AXUIElement.self), kAXChildrenAttribute as CFString, &childrenValue)
            let frames = ((childrenValue as? [AnyObject]) ?? []).compactMap { object -> String? in
                guard CFGetTypeID(object as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
                return frame(of: unsafeBitCast(object, to: AXUIElement.self)).map { NSStringFromRect($0) }
            }
            guard !frames.isEmpty else { continue }
            lines.append("\(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "-")]: \(frames.joined(separator: " "))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Target window

    private func targetApplication() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier, NSApp.keyWindow == nil {
            return lastActiveApp
        }
        return frontmost
    }

    private func focusedWindow() -> AXUIElement? {
        guard let app = targetApplication() else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        return element(application, kAXFocusedWindowAttribute) ?? element(application, kAXMainWindowAttribute)
    }

    private func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success,
              let value else { return false }
        return (value as? Bool) ?? false
    }

    // MARK: Frames

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let position = axValue(window, kAXPositionAttribute),
              let size = axValue(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    private func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }

    /// Size first, so a window that would not fit at the new origin shrinks before it moves; then the
    /// position; then the size once more for apps that clamp the size until the window is fully on screen.
    private func set(frame: CGRect, for window: AXUIElement) {
        setSize(frame.size, of: window)
        setPosition(frame.origin, of: window)
        setSize(frame.size, of: window)
    }

    private func setPosition(_ position: CGPoint, of window: AXUIElement) {
        var point = position
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private func setSize(_ size: CGSize, of window: AXUIElement) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    // MARK: Restore

    /// Remembers the frame before the first action on a window, so "Herstellen" returns to where the
    /// user left it rather than to the previous tile.
    private func remember(_ frame: CGRect, for key: WindowKey) {
        guard restoreFrames[key] == nil else { return }
        restoreFrames[key] = frame
        restoreOrder.append(key)
        if restoreOrder.count > restoreLimit {
            let oldest = restoreOrder.removeFirst()
            restoreFrames[oldest] = nil
        }
    }

    private func forget(_ key: WindowKey) {
        restoreFrames[key] = nil
        restoreOrder.removeAll { $0 == key }
    }
}

/// Hashable wrapper so AXUIElement references can key a dictionary. CFEqual treats two references to the
/// same window as equal, which is exactly what restore needs.
struct WindowKey: Hashable {
    let element: AXUIElement

    init(_ element: AXUIElement) { self.element = element }

    static func == (lhs: WindowKey, rhs: WindowKey) -> Bool { CFEqual(lhs.element, rhs.element) }

    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

enum ScreenGeometry {
    /// Usable area of every screen, converted from AppKit's bottom-left origin to the Accessibility
    /// top-left origin, sorted left to right so "next display" is predictable.
    static func visibleFrames() -> [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        let primaryHeight = primary.frame.maxY
        return NSScreen.screens.map { screen -> CGRect in
            let visible = screen.visibleFrame
            return CGRect(x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height)
        }.sorted { lhs, rhs in
            lhs.minX == rhs.minX ? lhs.minY < rhs.minY : lhs.minX < rhs.minX
        }
    }
}
