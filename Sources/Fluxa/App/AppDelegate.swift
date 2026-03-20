import AppKit

// MARK: - AppDelegate

/// NSApplicationDelegate for lifecycle management: cleanup on quit, global hotkey setup.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Weak reference to the ViewModel — set by FluxaApp when the popover first appears.
    weak var viewModel: PopoverViewModel? {
        didSet { wireShortcutIfNeeded() }
    }

    private let shortcut = GlobalShortcutService()
    private var shortcutRegistered = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcut.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.cleanup()
        shortcut.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Private

    /// Wires the hotkey toggle action to the ViewModel once it becomes available.
    private func wireShortcutIfNeeded() {
        guard !shortcutRegistered, let vm = viewModel else { return }
        shortcut.toggleAction = { [weak vm] in
            Task { @MainActor in vm?.toggleMenuBarWindow() }
        }
        shortcutRegistered = true
    }
}
