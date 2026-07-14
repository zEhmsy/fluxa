import SwiftUI

// MARK: - ActionListView

/// Scrollable list of action rows, driven by the user's ordering and visibility preferences.
struct ActionListView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(PopoverViewModel.self) private var viewModel

    /// Passed through to each row so momentary actions can close the popover.
    var closePopover: (() -> Void)?

    var body: some View {
        // No ScrollView: inside the MenuBarExtra window it reports zero ideal
        // height and the window (which sizes to the ideal size) collapses the
        // whole list. The popover holds at most 9 rows, so scrolling is not needed.
        VStack(spacing: 1) {
            ForEach(settings.visibleActions) { action in
                ActionRowView(action: action, closePopover: closePopover)
            }
        }
        .padding(.vertical, 6)
    }
}
