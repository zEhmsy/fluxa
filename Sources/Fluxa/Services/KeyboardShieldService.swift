import AppKit
import ApplicationServices

// MARK: - Keyboard Event Tap Context

/// Retained by `KeyboardShieldService` for as long as the event tap is installed. The callback is
/// a C function and cannot capture the service directly, so this small context keeps the tap
/// available when macOS temporarily disables it after a timeout or a secure-input transition.
private final class KeyboardEventTapContext {
    var tap: CFMachPort?
}

// MARK: - KeyboardShieldService

/// Blocks keyboard events globally until explicitly deactivated from Fluxa's toggle.
///
/// The mouse is intentionally left untouched so the user can always reopen the menu-bar popover
/// and switch the lock off. A compact, click-through HUD reports the active state without covering
/// the desktop. Filtering global keyboard events requires Accessibility permission on macOS.
@MainActor
final class KeyboardShieldService {

    enum ActivationError: LocalizedError {
        case accessibilityPermissionRequired
        case eventTapUnavailable

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionRequired:
                return "Grant Fluxa Accessibility access, then switch Lock Keyboard on again."
            case .eventTapUnavailable:
                return "Keyboard Lock could not start. Check Fluxa's Accessibility access and try again."
            }
        }
    }

    // MARK: - State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventTapContext: KeyboardEventTapContext?
    private var statusPanel: NSPanel?

    var isActive: Bool {
        guard let eventTap else { return false }
        return CFMachPortIsValid(eventTap)
    }

    // MARK: - Public API

    /// Starts a session-level event tap and leaves it active until `deactivate()` is called.
    func activate() throws {
        guard !isActive else { return }

        guard AXIsProcessTrusted() else {
            throw ActivationError.accessibilityPermissionRequired
        }

        let context = KeyboardEventTapContext()
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.keyboardEventMask,
            callback: Self.keyboardEventCallback,
            userInfo: contextPointer
        ) else {
            throw ActivationError.eventTapUnavailable
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw ActivationError.eventTapUnavailable
        }

        context.tap = tap
        eventTapContext = context
        eventTap = tap
        runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        showStatusPanel()
    }

    /// Removes the event tap and HUD. This is the only normal exit path while the app is running.
    func deactivate() {
        statusPanel?.close()
        statusPanel = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
        eventTapContext = nil
    }

    // MARK: - Event Tap

    private static let keyboardEventMask: CGEventMask = {
        let eventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        return eventTypes.reduce(CGEventMask(0)) { mask, eventType in
            mask | (CGEventMask(1) << eventType.rawValue)
        }
    }()

    private static let keyboardEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let context = Unmanaged<KeyboardEventTapContext>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = context.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)

        case .keyDown, .keyUp, .flagsChanged:
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Status HUD

    private func showStatusPanel() {
        guard statusPanel == nil,
              let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let panelSize = NSSize(width: 240, height: 52)
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.maxY - panelSize.height - 14
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        iconView.contentTintColor = .labelColor
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Keyboard locked")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        let instructionLabel = NSTextField(labelWithString: "Use the Fluxa toggle to unlock")
        instructionLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        instructionLabel.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [titleLabel, instructionLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        let content = NSStackView(views: [iconView, labels])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(content)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            content.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(lessThanOrEqualTo: effectView.trailingAnchor, constant: -14),
            content.centerYAnchor.constraint(equalTo: effectView.centerYAnchor)
        ])

        panel.contentView = effectView
        statusPanel = panel
        panel.orderFrontRegardless()
    }

    // MARK: - Accessibility

    static func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
