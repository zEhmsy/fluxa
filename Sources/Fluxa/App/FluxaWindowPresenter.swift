import AppKit
import SwiftUI

// MARK: - FluxaWindowPresenter

/// Coordinates SwiftUI `Window` scenes with AppKit so tool windows reliably become key and visible
/// after `openWindow` creates them. Calling `NSApp.activate` immediately after `openWindow` races the
/// scene creation; this registry waits for the actual NSWindow instead.
@MainActor
final class FluxaWindowPresenter {
    static let shared = FluxaWindowPresenter()

    private final class WeakWindow {
        weak var value: NSWindow?

        init(_ value: NSWindow) {
            self.value = value
        }
    }

    private var windows: [String: WeakWindow] = [:]
    private var pendingWindowIDs: Set<String> = []

    private init() {}

    func register(_ window: NSWindow, id: String) {
        windows[id] = WeakWindow(window)
        if pendingWindowIDs.contains(id) {
            foreground(window, id: id)
        }
    }

    /// Activates Fluxa and retries briefly while SwiftUI constructs a newly opened scene.
    func bringToFront(id: String) {
        NSApp.activate(ignoringOtherApps: true)
        pendingWindowIDs.insert(id)

        if let window = windows[id]?.value {
            foreground(window, id: id)
            return
        }

        Task { @MainActor [weak self] in
            for _ in 0..<12 {
                if let window = self?.windows[id]?.value {
                    self?.foreground(window, id: id)
                    return
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
    }

    private func foreground(_ window: NSWindow, id: String) {
        pendingWindowIDs.remove(id)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

// MARK: - Window Registration Bridge

private struct FluxaWindowReader: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> WindowReaderView {
        WindowReaderView(id: id)
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.id = id
        nsView.registerWindowIfAvailable()
    }

    final class WindowReaderView: NSView {
        var id: String

        init(id: String) {
            self.id = id
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            registerWindowIfAvailable()
        }

        func registerWindowIfAvailable() {
            guard let window else { return }
            FluxaWindowPresenter.shared.register(window, id: id)
        }
    }
}

extension View {
    /// Registers the NSWindow that hosts this SwiftUI scene without affecting its layout.
    func registersFluxaWindow(id: String) -> some View {
        background {
            FluxaWindowReader(id: id)
                .frame(width: 0, height: 0)
        }
    }
}
