import Carbon
import AppKit

// MARK: - GlobalShortcutService

/// Registers a system-wide hotkey (Cmd+Shift+F) using the Carbon EventHotKey API.
///
/// When the hotkey fires it invokes `toggleAction`, which the caller wires to
/// a closure that shows or hides the MenuBarExtra window.
///
/// Carbon hotkeys are global and do not require Accessibility permission.
final class GlobalShortcutService {

    // MARK: - Private

    private var hotKeyRef: EventHotKeyRef?
    private var screenDrawHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    /// Retained pointer passed to Carbon; released in unregister().
    private var retainedSelf: UnsafeMutableRawPointer?

    // MARK: - Public

    /// Called on hotkey press (Cmd+Shift+F). Wire this to show/hide the popover window.
    var toggleAction: (() -> Void)?

    /// Called on hotkey press (Cmd+Shift+D). Wire this to toggle Screen Draw mode.
    var screenDrawAction: (() -> Void)?

    // MARK: - API

    /// Registers the global hotkeys. Call after the app finishes launching.
    func register() {
        installEventHandler()
        registerHotKey()
    }

    /// Unregisters the hotkeys and removes the Carbon event handler.
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = screenDrawHotKeyRef {
            UnregisterEventHotKey(ref)
            screenDrawHotKeyRef = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        if let ptr = retainedSelf {
            Unmanaged<GlobalShortcutService>.fromOpaque(ptr).release()
            retainedSelf = nil
        }
    }

    // MARK: - Carbon Setup

    private func installEventHandler() {
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        retainedSelf = selfPtr

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventCallback,
            1,
            &spec,
            selfPtr,
            &eventHandlerRef
        )
    }

    private func registerHotKey() {
        // Cmd+Shift+F (Menu Bar Extra popover)
        let hotKeyID = EventHotKeyID(signature: fourCC("flxa"), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_F),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        // Cmd+Shift+D (Screen Draw overlay)
        let screenDrawID = EventHotKeyID(signature: fourCC("flxa"), id: 2)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_D),
            UInt32(cmdKey | shiftKey),
            screenDrawID,
            GetApplicationEventTarget(),
            0,
            &screenDrawHotKeyRef
        )
    }

    // MARK: - Internal

    fileprivate func hotKeyPressed(id: UInt32) {
        DispatchQueue.main.async { [weak self] in
            if id == 1 {
                self?.toggleAction?()
            } else if id == 2 {
                self?.screenDrawAction?()
            }
        }
    }
}

// MARK: - Carbon Callback (file-scope C function)

private func hotKeyEventCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let ptr = userData, let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let service = Unmanaged<GlobalShortcutService>.fromOpaque(ptr).takeUnretainedValue()
    service.hotKeyPressed(id: hotKeyID.id)
    return noErr
}

// MARK: - Helpers

private func fourCC(_ string: StaticString) -> FourCharCode {
    let bytes = string.utf8Start
    return FourCharCode(bytes[0]) << 24
        | FourCharCode(bytes[1]) << 16
        | FourCharCode(bytes[2]) << 8
        | FourCharCode(bytes[3])
}
