import AppKit
import SwiftUI

// MARK: - MenuBarCalloutPresenter

/// First-launch pointer to the menu bar icon: a sunrise card hung just under the status item. An
/// agent app has no Dock icon or window to point at, so this is how a new user finds Fluxa. The panel
/// joins every Space, full-screen ones included, because a first launch from a full-screen terminal
/// would otherwise put the card where nobody looks.
@MainActor
final class MenuBarCalloutPresenter {
    static let shared = MenuBarCalloutPresenter()

    private static let size = NSSize(width: 320, height: 188)
    private var panel: NSPanel?
    private var tracking: Task<Void, Never>?
    private let anchor = CalloutAnchor()

    func show(onPrimary: @escaping () -> Void) {
        guard panel == nil else { return }
        // The status item is placed a few run-loop turns after the label's first task. If it never
        // turns up (hidden behind the notch, say), point at the right end of the main menu bar.
        Task {
            for _ in 0..<40 {
                if let frame = Self.statusItemFrame() {
                    present(below: frame, onPrimary: onPrimary)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let screen = NSScreen.main else { return }
            present(below: NSRect(x: screen.frame.maxX - 200, y: screen.visibleFrame.maxY, width: 0, height: 0),
                    onPrimary: onPrimary)
        }
    }

    private func present(below frame: NSRect, onPrimary: @escaping () -> Void) {
        let panel = MenuBarCalloutPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let content = MenuBarCalloutView(
            anchor: anchor,
            onSkip: { [weak self] in self?.dismiss() },
            onPrimary: { [weak self] in
                self?.dismiss()
                onPrimary()
            }
        )
        // Without this the hosting view resizes the panel to the copy's ideal height.
        let hostingView = NSHostingView(rootView: content.frame(width: Self.size.width, height: Self.size.height))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        self.panel = panel
        place(below: frame)
        panel.orderFrontRegardless()

        // The item keeps moving after it first appears: the strip widens leftward as its metrics
        // load, and other apps' items can push it. Follow it for as long as the card is up.
        tracking = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let frame = Self.statusItemFrame() else { continue }
                self.place(below: frame)
            }
        }
    }

    private func place(below frame: NSRect) {
        guard let panel,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main else { return }
        let x = min(max(frame.midX - Self.size.width / 2, screen.visibleFrame.minX + 8),
                    screen.visibleFrame.maxX - Self.size.width - 8)
        let origin = NSPoint(x: x, y: screen.visibleFrame.maxY - Self.size.height - 8)
        guard origin != panel.frame.origin || anchor.arrowOffset != frame.midX - (x + Self.size.width / 2) else { return }
        panel.setFrameOrigin(origin)
        anchor.arrowOffset = frame.midX - (x + Self.size.width / 2)
    }

    /// Called once the view has played its sunset; the view owns the exit timing.
    private func dismiss() {
        tracking?.cancel()
        tracking = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    /// Since macOS 26 the status item's own `NSStatusBarWindow` reports a placeholder frame, often
    /// off every screen. The app's accessibility tree has the real one; the window server's copy,
    /// named after the app, is the backup for when that tree is unavailable.
    private static func statusItemFrame() -> NSRect? {
        guard let topLeft = accessibilityFrame() ?? windowServerFrame(),
              let primary = NSScreen.screens.first else {
            return nil
        }
        // Both sources are top-left based on the primary display; AppKit's frames are bottom-left.
        return NSRect(x: topLeft.minX, y: primary.frame.maxY - topLeft.maxY, width: topLeft.width, height: topLeft.height)
    }

    private static func accessibilityFrame() -> CGRect? {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var bar: CFTypeRef?
        var items: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID(),
              AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &items) == .success,
              let item = (items as? [AXUIElement])?.first else {
            return nil
        }
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0 else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    /// Control Center draws the item in a window named after the owning app's bundle identifier, or
    /// its PID for an unbundled build, though not reliably: names can read `Item-0` instead.
    private static func windowServerFrame() -> CGRect? {
        // An unbundled development build shares the embedded bundle identifier with any installed
        // copy, and its own item can appear after the installed one, so it matches on its PID alone.
        let isBundled = Bundle.main.bundleURL.pathExtension == "app"
        let name = isBundled ? Bundle.main.bundleIdentifier : String(ProcessInfo.processInfo.processIdentifier)
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              let item = windows.first(where: {
                  ($0[kCGWindowLayer as String] as? Int) == statusLevel && ($0[kCGWindowName as String] as? String) == name
              }),
              let bounds = item[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: bounds)
    }
}

/// Horizontal distance from the card's centre to the status item's, so the arrow points at it even
/// when the card is pushed in from the screen edge.
@MainActor @Observable
private final class CalloutAnchor {
    var arrowOffset: CGFloat = 0
}

/// Key-capable so the buttons respond on the first click, without activating the app behind it.
private final class MenuBarCalloutPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - MenuBarCalloutView

/// Mirrors the Horizon reference in Fluxa's brand colours: colour rises, then the copy fades in; on either button the copy
/// fades first and the colour sets back down before the panel goes.
private struct MenuBarCalloutView: View {
    let anchor: CalloutAnchor
    let onSkip: () -> Void
    let onPrimary: () -> Void

    @State private var revealed = false
    @State private var showsCopy = false

    private static let icon: NSImage? = {
        guard let url = Bundle.fluxaResources.url(forResource: "menu-icon", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        ZStack {
            AnimatedMeshGradientView(revealed: revealed)
            copy
                .opacity(showsCopy ? 1 : 0)
                .offset(y: showsCopy ? 0 : 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .dark)
        .onAppear {
            revealed = true
            withAnimation(.easeOut(duration: 0.35).delay(AnimatedMeshGradientView.riseDuration * 0.6)) {
                showsCopy = true
            }
        }
    }

    private var copy: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .offset(x: max(-130, min(130, anchor.arrowOffset)))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let icon = Self.icon {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16)
                    }
                    Text("Fluxa lives up here").font(.system(size: 15, weight: .bold))
                }
                Text("Your controls and live stats are one click away in the menu bar. Click the icon any time.")
                    .font(.system(size: 12))
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button("Skip") { leave(then: onSkip) }
                    .buttonStyle(CalloutButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button("Set Up Permissions") { leave(then: onPrimary) }
                    .buttonStyle(CalloutButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }

    private func leave(then action: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.2)) { showsCopy = false }
        revealed = false
        Task {
            try? await Task.sleep(for: .seconds(AnimatedMeshGradientView.riseDuration * 0.7 + 0.05))
            action()
        }
    }
}

private struct CalloutButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? ControlDeckPalette.dark.brandBlue : Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(prominent ? Color.white : Color.white.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(prominent ? 0 : 0.3))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
