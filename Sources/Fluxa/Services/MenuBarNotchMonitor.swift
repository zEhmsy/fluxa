import AppKit
import FluxaCore

/// Watches Fluxa's status item and reports when the notch hides it, so the label can fall back to
/// the logo. Pure decisions live in `NotchCollapse`; this only gathers geometry and events.
@MainActor
final class MenuBarNotchMonitor {
    var onChange: (@MainActor (Bool) -> Void)?

    private var collapsed = false
    private var lastChange: Date?
    private var fullWidth: Double = 0
    private var observers: [NSObjectProtocol] = []
    private var pendingEvaluation: Task<Void, Never>?
    private var warnedMissingWindow = false

    // MARK: - Lifecycle

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        })
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let window = note.object as? NSWindow,
                          Self.isStatusWindow(window) else { return }
                    self.evaluate()
                }
            })
        }
        // The status window can appear after the label does.
        for delay in [0.5, 2.0] {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.evaluate()
            }
        }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
    }

    /// Called by the label when the full strip's width changes.
    func update(fullWidth: Double) {
        self.fullWidth = fullWidth
        evaluate()
    }

    // MARK: - Evaluation

    private func evaluate() {
        let window = Self.statusWindow()
        if window == nil, !warnedMissingWindow {
            warnedMissingWindow = true
            NSLog("Fluxa: status bar window not found; notch collapse inactive")
        }
        let now = Date()
        let item = window.map { NotchCollapse.Frame(minX: $0.frame.minX, maxX: $0.frame.maxX) }
        let next = NotchCollapse.nextState(
            collapsed: collapsed, item: item, fullWidth: fullWidth,
            notch: Self.notch(for: window), lastChange: lastChange, now: now)

        if next != collapsed {
            collapsed = next
            lastChange = now
            onChange?(next)
        }
        scheduleDeferredEvaluation(now: now)
    }

    /// A change blocked by the dwell would otherwise wait for the next window event.
    private func scheduleDeferredEvaluation(now: Date) {
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
        guard let lastChange else { return }
        let remaining = NotchCollapse.minDwell - now.timeIntervalSince(lastChange)
        guard remaining > 0 else { return }
        pendingEvaluation = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining + 0.1))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    // MARK: - Geometry

    private static func isStatusWindow(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("NSStatusBarWindow")
    }

    private static func statusWindow() -> NSWindow? {
        NSApp.windows.first(where: isStatusWindow)
    }

    private static func notch(for window: NSWindow?) -> NotchGeometry? {
        guard let screen = window?.screen ?? NSScreen.main,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let originX = screen.frame.minX
        return NotchGeometry(gapMinX: originX + left.maxX, gapMaxX: originX + right.minX)
    }
}
