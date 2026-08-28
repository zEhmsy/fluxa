import AppKit

// MARK: - AppDelegate

/// NSApplicationDelegate for lifecycle management: cleanup on quit, global hotkey setup.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // The delegate owns app-lifetime state. Cleanup and the updater are wired before any views
    // appear, without reaching into a not-yet-installed SwiftUI property wrapper from App.init.
    let settings: AppSettings
    let viewModel: PopoverViewModel

    private let shortcut = GlobalShortcutService()
    private var shortcutRegistered = false

    override init() {
        let settings = AppSettings()
        self.settings = settings
        viewModel = PopoverViewModel(settings: settings)
        super.init()
        wireShortcutIfNeeded()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcut.register()
        viewModel.updates.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.cleanup()
        shortcut.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Private

    /// Wires the hotkey toggle action to the ViewModel once it becomes available.
    private func wireShortcutIfNeeded() {
        guard !shortcutRegistered else { return }
        let vm = viewModel
        shortcut.toggleAction = { [weak vm] in
            Task { @MainActor in vm?.toggleMenuBarWindow() }
        }
        shortcutRegistered = true
    }
}
