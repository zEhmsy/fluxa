import AppKit
import SwiftUI

// MARK: - ScreenDrawOverlayPanel

/// Transparent fullscreen panel covering a specific screen to host the drawing canvas.
@MainActor
final class ScreenDrawOverlayPanel: NSPanel {

    weak var service: ScreenDrawService?
    var targetScreen: NSScreen?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func create(screen: NSScreen, service: ScreenDrawService) -> ScreenDrawOverlayPanel {
        let panel = ScreenDrawOverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        panel.targetScreen = screen
        panel.service = service
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false

        panel.setFrame(screen.frame, display: false)

        let canvasView = ScreenDrawCanvasView(service: service, screenFrame: screen.frame)
        let hostingView = NSHostingView(rootView: canvasView)
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        return panel
    }

    override func mouseDown(with event: NSEvent) {
        guard let targetScreen else { return }
        let point = locationInScreen(for: event, screen: targetScreen)
        service?.handleMouseDown(at: point, screen: targetScreen)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let targetScreen else { return }
        let point = locationInScreen(for: event, screen: targetScreen)
        service?.handleMouseDragged(to: point, screen: targetScreen)
    }

    override func mouseUp(with event: NSEvent) {
        guard let targetScreen else { return }
        let point = locationInScreen(for: event, screen: targetScreen)
        service?.handleMouseUp(at: point, screen: targetScreen)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let screen = targetScreen ?? NSScreen.main else { return }
        let point = locationInScreen(for: event, screen: screen)
        service?.handleMouseMoved(to: point)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let service, service.activeTool == .spotlight else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 1.5 : event.scrollingDeltaY * 10.0
        service.adjustSpotlightRadius(delta: delta)
    }

    private func locationInScreen(for event: NSEvent, screen: NSScreen) -> CGPoint {
        // AppKit window coordinates have origin at bottom-left
        let locationInWindow = event.locationInWindow
        // Invert Y to match standard SwiftUI Canvas top-left origin
        let flippedY = screen.frame.height - locationInWindow.y
        return CGPoint(x: locationInWindow.x, y: flippedY)
    }
}
