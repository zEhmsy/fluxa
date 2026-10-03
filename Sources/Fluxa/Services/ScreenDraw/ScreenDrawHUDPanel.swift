import AppKit
import SwiftUI

// MARK: - ScreenDrawHUDPanel

/// Floating, draggable AppKit panel hosting the ScreenDrawHUDView toolbar.
@MainActor
final class ScreenDrawHUDPanel: NSPanel {

    static let originXKey = "fluxa_screen_draw_hud_origin_x"
    static let originYKey = "fluxa_screen_draw_hud_origin_y"

    private var isAdjustingSize = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        guard !isAdjustingSize else { return }
        UserDefaults.standard.set(newOrigin.x, forKey: Self.originXKey)
        UserDefaults.standard.set(newOrigin.y, forKey: Self.originYKey)
    }

    /// Re-anchors the panel frame to maintain its horizontal center (midX) when expanding or collapsing.
    func updateSizeAnchored() {
        guard let contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        let newSize = contentView.fittingSize
        guard newSize.width > 0, newSize.height > 0 else { return }

        let currentMidX = frame.midX
        let newX = currentMidX - newSize.width / 2.0
        let newOrigin = NSPoint(x: newX, y: frame.origin.y)

        isAdjustingSize = true
        setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: false)
        isAdjustingSize = false
    }

    static func create(service: ScreenDrawService) -> ScreenDrawHUDPanel {
        let panel = ScreenDrawHUDPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The SwiftUI view draws its own shadow inside a transparent margin, which also lets the
        // cut-corner Cyber silhouette cast a matching shadow.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = false

        panel.sharingType = service.hideHUDFromScreenCapture ? .none : .readOnly

        let hudView = ScreenDrawHUDView(service: service)
            .fluxaVisualStyle(from: service.settings)
        let hostingView = NSHostingView(rootView: hudView)
        panel.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        // Position: restore saved coordinates on target screen or center on primary screen.
        let size = hostingView.fittingSize

        if let savedX = UserDefaults.standard.object(forKey: originXKey) as? CGFloat,
           let savedY = UserDefaults.standard.object(forKey: originYKey) as? CGFloat {
            let savedPoint = NSPoint(x: savedX, y: savedY)
            let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(savedPoint) }) ?? NSScreen.main ?? NSScreen.screens.first
            if let screenRect = targetScreen?.visibleFrame {
                let clampedX = min(max(savedX, screenRect.minX), screenRect.maxX - size.width)
                let clampedY = min(max(savedY, screenRect.minY), screenRect.maxY - size.height)
                panel.setFrame(NSRect(origin: NSPoint(x: clampedX, y: clampedY), size: size), display: true)
            }
        } else if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let origin = NSPoint(
                x: screenRect.midX - size.width / 2,
                y: screenRect.minY + 24 - ScreenDrawHUDView.shadowMargin
            )
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }

        return panel
    }
}
