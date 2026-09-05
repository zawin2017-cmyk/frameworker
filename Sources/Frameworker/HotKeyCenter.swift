import AppKit
import Carbon

/// Registers global hotkeys through Carbon's RegisterEventHotKey. The process is only woken when one of
/// the registered combinations is pressed, so the idle cost is zero: no event tap, no key monitoring,
/// no polling. Registration does not require Accessibility permission either.
final class HotKeyCenter {
    var handler: ((WindowAction) -> Void)?

    /// Actions whose combination could not be registered, almost always because another app (Rectangle,
    /// for instance) already owns it.
    private(set) var failed: Set<WindowAction> = []

    private var eventHandler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private var bindings: [WindowAction: Shortcut] = [:]
    private var isPaused = false

    private static let signature: OSType = 0x4652_4D57 // "FRMW"

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec, context, &eventHandler)
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// Replaces every registration with `shortcuts`.
    func bind(_ shortcuts: [WindowAction: Shortcut]) {
        bindings = shortcuts
        apply()
    }

    /// Temporarily releases every hotkey, so the settings window can record a combination that is
    /// currently bound without triggering it.
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        unregisterAll()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        apply()
    }

    fileprivate func fire(id: UInt32) {
        guard let action = WindowAction.from(index: Int(id)) else { return }
        handler?(action)
    }

    private func apply() {
        unregisterAll()
        failed = []
        guard !isPaused else { return }
        for (action, shortcut) in bindings {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: HotKeyCenter.signature, id: UInt32(action.index))
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                             GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                registrations.append(reference)
            } else {
                failed.insert(action)
            }
        }
    }

    private func unregisterAll() {
        registrations.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll()
    }
}

/// C callback for Carbon. It cannot capture context, so the HotKeyCenter travels in the user-data pointer.
private let hotKeyCallback: EventHandlerUPP = { _, event, context in
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue().fire(id: hotKeyID.id)
    return noErr
}
