import AppKit

// MARK: - ScreenCleanPanel

/// Borderless windows do not become key by default. Screen Clean needs each overlay to accept the
/// first click so dismissal behaves identically on the primary and secondary displays.
private final class ScreenCleanPanel: NSPanel {

    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            onDismiss?()
        default:
            super.sendEvent(event)
        }
    }
}

// MARK: - ScreenCleanContentView

/// Receives the first click even when its panel is not the key window. A local event monitor only
/// sees events delivered to the active panel, which made Screen Clean impossible to dismiss by
/// clicking a secondary display.
private final class ScreenCleanContentView: NSView {

    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onDismiss()
    }

    override func rightMouseDown(with event: NSEvent) {
        onDismiss()
    }

    override func otherMouseDown(with event: NSEvent) {
        onDismiss()
    }
}

// MARK: - ScreenCleanService

/// Presents a full-screen black overlay on all displays to allow the user to physically
/// clean the screen without triggering accidental input.
///
/// How it works:
/// - Creates an `NSPanel` per screen at window level `.screenSaver` (above all other windows,
///   including the menu bar and Dock).
/// - Each panel owns a content view that dismisses on the first mouse click, key or not.
/// - Dismisses on ESC (keyCode 53) through a local key monitor.
/// - Rebuilds the overlays if displays are connected, disconnected, or rearranged while active.
///
/// Notes:
/// - Does NOT require Accessibility permission — local event monitors work for key windows.
/// - The menu bar icon remains clickable (system chrome is above .screenSaver level).
@MainActor
final class ScreenCleanService {

    // MARK: - State

    private var panels: [NSPanel] = []
    private var eventMonitor: Any?
    private var screenParametersObserver: NSObjectProtocol?
    private var previouslyActiveApplication: NSRunningApplication?

    private(set) var isActive = false

    // MARK: - Public API

    /// Shows the black overlay on all connected screens.
    func activate() {
        guard !isActive else { return }
        let currentApplication = NSRunningApplication.current
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.processIdentifier != currentApplication.processIdentifier {
            previouslyActiveApplication = frontmostApplication
        }
        isActive = true

        installDismissMonitor()
        installScreenParametersObserver()
        rebuildPanels()
    }

    /// Removes all overlay panels and restores normal desktop view.
    func deactivate() {
        let applicationToRestore = previouslyActiveApplication
        previouslyActiveApplication = nil
        isActive = false
        removeDismissMonitor()
        removeScreenParametersObserver()
        panels.forEach { $0.close() }
        panels.removeAll()

        if let applicationToRestore, !applicationToRestore.isTerminated {
            NSApp.yieldActivation(to: applicationToRestore)
            _ = applicationToRestore.activate(from: .current, options: [])
        }
    }

    // MARK: - Panel Construction

    private func makeCleanPanel(for screen: NSScreen) -> NSPanel {
        let panel = ScreenCleanPanel(
            // This initializer interprets contentRect relative to `screen`. Passing screen.frame
            // here applied the display origin twice and placed secondary panels off-screen.
            contentRect: .zero,
            styleMask: [.borderless],
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
        panel.becomesKeyOnlyIfNeeded = false

        // setFrame expects global display coordinates, so the screen origin is applied exactly once.
        panel.setFrame(screen.frame, display: false)

        let contentView = ScreenCleanContentView { [weak self] in
            self?.deactivate()
        }
        panel.onDismiss = { [weak self] in
            self?.deactivate()
        }
        panel.contentView = contentView

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
        label.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        return panel
    }

    /// Recreates all panels from the current screen list. Display changes are rare and replacing
    /// the small set atomically avoids stale frames after a monitor is unplugged or rearranged.
    private func rebuildPanels() {
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map(makeCleanPanel(for:))

        for panel in panels.dropLast() {
            panel.orderFrontRegardless()
        }
        panels.last?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panels.last?.makeKey()
    }

    // MARK: - Event Monitoring

    private func installDismissMonitor() {
        // Only ESC needs the key panel. Mouse input is handled by each panel's content view, so a
        // click on any display works without a global monitor or Accessibility permission.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ESC key = keyCode 53
            if event.type == .keyDown && event.keyCode == 53 {
                Task { @MainActor in self?.deactivate() }
                return nil // swallow the event
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

    // MARK: - Display Changes

    private func installScreenParametersObserver() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.isActive == true else { return }
                self?.rebuildPanels()
            }
        }
    }

    private func removeScreenParametersObserver() {
        if let observer = screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
            screenParametersObserver = nil
        }
    }
}
