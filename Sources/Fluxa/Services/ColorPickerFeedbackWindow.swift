import AppKit
import SwiftUI

// MARK: - ColorPickerFeedbackPanel

/// A visual-only panel: it can neither become key nor enter the normal window cycle.
private final class ColorPickerFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - ColorPickerFeedbackPresenter

/// Owns the short-lived success HUD and releases it after the fade-out completes.
@MainActor
final class ColorPickerFeedbackPresenter {
    private static let panelSize = NSSize(width: 200, height: 56)

    private var panel: NSPanel?
    private var lifecycleTask: Task<Void, Never>?

    func show(color: NSColor, hex: String) {
        dismissCurrentPanel()

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first else {
            return
        }

        let panel = makePanel(color: color, hex: hex, screen: screen, mouseLocation: mouse)
        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        lifecycleTask = Task { @MainActor [weak self, weak panel] in
            do {
                try await Task.sleep(for: .seconds(2.0))
            } catch {
                return
            }

            guard let panel, self?.panel === panel else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                panel.animator().alphaValue = 0
            }

            guard self?.panel === panel else { return }
            panel.orderOut(nil)
            panel.close()
            self?.panel = nil
            self?.lifecycleTask = nil
        }
    }

    private func makePanel(color: NSColor, hex: String, screen: NSScreen, mouseLocation: NSPoint) -> NSPanel {
        let panel = ColorPickerFeedbackPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none

        // Position slightly above the cursor location, clamped to screen bounds
        let x = min(max(mouseLocation.x - Self.panelSize.width / 2, screen.visibleFrame.minX + 16), screen.visibleFrame.maxX - Self.panelSize.width - 16)
        let y = min(max(mouseLocation.y + 24, screen.visibleFrame.minY + 16), screen.visibleFrame.maxY - Self.panelSize.height - 16)
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        let contentView = NSHostingView(rootView: ColorPickerFeedbackContent(color: color, hex: hex))
        contentView.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = contentView
        return panel
    }

    private func dismissCurrentPanel() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

// MARK: - ColorPickerFeedbackContent

private struct ColorPickerFeedbackContent: View {
    let color: NSColor
    let hex: String

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: color))
                .frame(width: 28, height: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(hex)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("Copied to clipboard")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: 200, height: 56)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FluxaTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Copied color \(hex)")
    }
}
