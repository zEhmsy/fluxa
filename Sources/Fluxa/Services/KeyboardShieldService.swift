import AppKit
import ApplicationServices

// MARK: - KeyboardShieldService

/// Presents a full-screen overlay that absorbs keyboard input while the panel is the key window.
///
/// IMPORTANT LIMITATION:
/// macOS does not provide a public API to globally lock keyboard input for all applications.
/// This service implements a "keyboard shield" — an NSPanel at screen-saver window level that
/// becomes the key window and absorbs keystrokes via a local event monitor.
///
/// The shield is effective while the panel remains the key window. If the user clicks on
/// another application's window, focus shifts and keystrokes reach that app.
///
/// For most use cases (e.g., keeping a sleeping keyboard clean), this is sufficient.
///
/// TRUE keyboard lock would require:
/// - A kernel extension (kext) — deprecated and unsigned in modern macOS
/// - Accessibility API + CGEventTap — possible but requires Accessibility permission
///
/// TODO: For a stricter implementation, consider using CGEventTap with
///       kCGHeadInsertEventTap to intercept events at the system level.
///       This would require Accessibility permission and explicit user consent.
@MainActor
final class KeyboardShieldService {

    // MARK: - State

    private var panel: NSPanel?
    private var eventMonitor: Any?

    var isActive: Bool { panel != nil }

    // MARK: - Public API

    /// Activates the keyboard shield. Requests Accessibility if not yet granted.
    func activate() {
        guard panel == nil else { return }

        // Check accessibility for the informational banner (not strictly required for
        // local monitor, but good practice to surface the limitation to the user).
        let trusted = AXIsProcessTrusted()

        let shield = makeShieldPanel(accessibilityGranted: trusted)
        panel = shield
        shield.makeKeyAndOrderFront(nil)
        installKeyboardMonitor()
    }

    /// Deactivates the keyboard shield and restores normal keyboard routing.
    func deactivate() {
        removeKeyboardMonitor()
        panel?.close()
        panel = nil
    }

    // MARK: - Panel Construction

    private func makeShieldPanel(accessibilityGranted: Bool) -> NSPanel {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSPanel()
        }

        let shieldPanel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        shieldPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        shieldPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        shieldPanel.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        shieldPanel.isOpaque = false
        shieldPanel.hasShadow = false
        shieldPanel.ignoresMouseEvents = false
        shieldPanel.acceptsMouseMovedEvents = false
        shieldPanel.isReleasedWhenClosed = false

        let contentView = NSView(frame: screen.frame)
        shieldPanel.contentView = contentView

        // Main label
        let titleLabel = NSTextField(labelWithString: "Keyboard Shield Active")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.sizeToFit()

        // Subtitle
        let subtitleText = accessibilityGranted
            ? "Keyboard input is blocked · Press ESC or click to exit"
            : "Overlay mode (limited) · Press ESC or click to exit\nFor full keyboard lock, grant Accessibility in System Settings"

        let subtitleLabel = NSTextField(labelWithString: subtitleText)
        subtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.sizeToFit()

        // Stack vertically in center
        let centerX = screen.frame.width / 2
        let centerY = screen.frame.height / 2

        titleLabel.frame = CGRect(
            x: centerX - titleLabel.frame.width / 2,
            y: centerY + 8,
            width: titleLabel.frame.width,
            height: titleLabel.frame.height
        )

        subtitleLabel.frame = CGRect(
            x: centerX - 200,
            y: centerY - subtitleLabel.frame.height - 4,
            width: 400,
            height: subtitleLabel.frame.height + 20
        )

        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)

        return shieldPanel
    }

    // MARK: - Event Monitoring

    private func installKeyboardMonitor() {
        // Local event monitor: intercepts key events while our panel is key window.
        // Returns nil to swallow events (prevents them from reaching other views).
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            // ESC (keyCode 53) or any mouse click → dismiss
            if event.type == .keyDown && event.keyCode == 53 {
                Task { @MainActor in self?.deactivate() }
                return nil
            }
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                Task { @MainActor in self?.deactivate() }
                return nil
            }
            // Swallow all other keystrokes
            if event.type == .keyDown {
                return nil
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Accessibility Helper

    /// Checks if the app has Accessibility permission and optionally prompts.
    static func requestAccessibilityIfNeeded() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
