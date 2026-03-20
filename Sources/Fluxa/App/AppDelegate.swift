import AppKit

// MARK: - AppDelegate

/// Minimal NSApplicationDelegate for lifecycle cleanup.
/// Ensures all system resources (IOKit assertions, NSPanels) are released on quit.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Weak reference to the ViewModel — set by FluxaApp on init.
    weak var viewModel: PopoverViewModel?

    func applicationWillTerminate(_ notification: Notification) {
        // Release Keep Awake IOKit assertion, dismiss any overlay panels.
        viewModel?.cleanup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Returning false keeps the menu bar app running when the popover is closed.
        return false
    }
}
