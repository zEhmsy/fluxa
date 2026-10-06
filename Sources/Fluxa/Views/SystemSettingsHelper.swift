import AppKit
import SwiftUI

// MARK: - SystemSettingsHelperPresenter

/// A small panel docked over the bottom of the System Settings window while a list-based permission is pending,
/// holding a Fluxa tile the user can drag straight into the list. Privacy lists accept a dropped app
/// bundle, which is quicker and less error-prone than + and a file browser. The panel follows the
/// window and is only shown while System Settings or Fluxa is in front.
@MainActor
final class SystemSettingsHelperPresenter {
    static let shared = SystemSettingsHelperPresenter()

    private static let size = NSSize(width: 380, height: 92)
    private static let settingsBundleID = "com.apple.systempreferences"

    private var panel: NSPanel?
    private var tracking: Task<Void, Never>?

    func show(permission: String, onClose: @escaping () -> Void) {
        dismiss()

        let panel = SystemSettingsHelperPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false

        let hostingView = NSHostingView(
            rootView: SystemSettingsHelperView(
                permission: permission,
                onClose: onClose,
                // After a drop macOS asks for Touch ID or the password; the helper would sit over
                // that prompt, and its job is done. The caller keeps watching for the grant.
                onDropped: { [weak self] in self?.dismiss() }
            )
                .frame(width: Self.size.width, height: Self.size.height)
        )
        // Without this the hosting view resizes the panel to the content's ideal size.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        self.panel = panel

        // System Settings takes a moment to open and animate into place, and the user may move it.
        tracking = Task { [weak self] in
            while !Task.isCancelled {
                self?.follow()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func dismiss() {
        tracking?.cancel()
        tracking = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    private func follow() {
        guard let panel else { return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard front == Self.settingsBundleID || front == Bundle.main.bundleIdentifier,
              let settings = Self.settingsWindowFrame() else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        // Overlapping the window's bottom edge, as Codex does: below it is often off-screen, since
        // System Settings tends to open tall enough to reach the bottom of the display.
        var origin = NSPoint(x: settings.midX - Self.size.width / 2, y: settings.minY + 16)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(settings) }) {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - Self.size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - Self.size.height - 8)
        }
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        }
    }

    /// Window bounds are readable without Screen Recording access; only titles need it.
    private static func settingsWindowFrame() -> NSRect? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleID).first?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let window = windows.first(where: {
                  ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
              }),
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds),
              let primary = NSScreen.screens.first else {
            return nil
        }
        // Window-server bounds are top-left based on the primary display; AppKit's are bottom-left.
        return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Key-capable so the close button responds on the first click, without activating Fluxa.
private final class SystemSettingsHelperPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - SystemSettingsHelperView

private struct SystemSettingsHelperView: View {
    let permission: String
    let onClose: () -> Void
    let onDropped: () -> Void

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Fluxa"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ControlDeckPalette.dark.brandBlue)
                (Text("Drag ") + Text(appName).bold() + Text(" to the list above to allow ") + Text(permission).bold())
                    .font(.system(size: 12))
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            dragTile
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .environment(\.colorScheme, .dark)
    }

    private var dragTile: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path))
                .resizable()
                .frame(width: 22, height: 22)
            Text(appName)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .overlay(AppBundleDragSource(onDropped: onDropped))
        .help("Drag into the Accessibility list")
    }
}

// MARK: - AppBundleDragSource

/// Drags the app bundle's file URL. AppKit rather than `onDrag`, which has no way to learn whether
/// the drag ended in a drop or was abandoned.
private struct AppBundleDragSource: NSViewRepresentable {
    let onDropped: () -> Void

    func makeNSView(context: Context) -> DragSourceView {
        DragSourceView(onDropped: onDropped)
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.onDropped = onDropped
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var onDropped: () -> Void

        init(onDropped: @escaping () -> Void) {
            self.onDropped = onDropped
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDragged(with event: NSEvent) {
            let url = Bundle.main.bundleURL
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let location = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: location.x - 16, y: location.y - 16, width: 32, height: 32), contents: icon)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .link, .generic] : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            guard !operation.isEmpty else { return }
            onDropped()
        }
    }
}
