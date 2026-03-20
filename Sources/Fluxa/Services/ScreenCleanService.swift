import AppKit
import SwiftUI

// MARK: - ScreenCleanService

/// Presents a full-screen black overlay on all displays to allow the user to physically
/// clean the screen without triggering accidental input.
///
/// How it works:
/// - Creates an `NSPanel` per screen at window level `.screenSaver` (above all other windows,
///   including the menu bar and Dock).
/// - Absorbs mouse events via the panel being the key window.
/// - Dismisses on ESC (keyCode 53) or any mouse click via a local event monitor.
///
/// Notes:
/// - Does NOT require Accessibility permission — local event monitors work for key windows.
/// - The menu bar icon remains clickable (system chrome is above .screenSaver level).
@MainActor
final class ScreenCleanService {

    // MARK: - State

    private var panels: [NSPanel] = []
    private var eventMonitor: Any?

    var isActive: Bool { !panels.isEmpty }

    // MARK: - Public API

    /// Shows the black overlay on all connected screens.
    func activate() {
        guard panels.isEmpty else { return }

        for screen in NSScreen.screens {
            let panel = makeCleanPanel(for: screen)
            panels.append(panel)
            panel.makeKeyAndOrderFront(nil)
        }

        installDismissMonitor()
    }

    /// Removes all overlay panels and restores normal desktop view.
    func deactivate() {
        removeDismissMonitor()
        panels.forEach { $0.close() }
        panels.removeAll()
    }

    // MARK: - Panel Construction

    private func makeCleanPanel(for screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = false
        panel.isReleasedWhenClosed = false

        // Overlay label — subtle instruction text in the center
        let label = NSTextField(labelWithString: "Screen Clean Mode\nPress ESC or click anywhere to exit")
        label.alignment = .center
        label.textColor = NSColor.white.withAlphaComponent(0.15)
        label.font = NSFont.systemFont(ofSize: 14, weight: .light)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.maximumNumberOfLines = 2
        label.sizeToFit()

        // Center label on screen
        let screenSize = screen.frame.size
        label.frame = CGRect(
            x: (screenSize.width - label.frame.width) / 2,
            y: (screenSize.height - label.frame.height) / 2,
            width: label.frame.width,
            height: label.frame.height
        )

        panel.contentView?.addSubview(label)
        return panel
    }

    // MARK: - Event Monitoring

    private func installDismissMonitor() {
        // Local monitor: works because our panel is the key window at .screenSaver level.
        // No Accessibility permission required for local monitors.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            // ESC key = keyCode 53
            if event.type == .keyDown && event.keyCode == 53 {
                Task { @MainActor in self?.deactivate() }
                return nil // swallow the event
            }
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                Task { @MainActor in self?.deactivate() }
                return nil
            }
            return event
        }
    }

    private func removeDismissMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
