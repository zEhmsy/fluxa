import SwiftUI

// MARK: - ActionListView

/// Scrollable list of action rows, driven by the user's ordering and visibility preferences.
struct ActionListView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(PopoverViewModel.self) private var viewModel

    /// Passed through to each row so momentary actions can close the popover.
    var closePopover: (() -> Void)?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(settings.visibleActions.enumerated()), id: \.element.id) { index, action in
                    ActionRowView(action: action, closePopover: closePopover)

                    // Divider between rows (not after the last one)
                    if index < settings.visibleActions.count - 1 {
                        Divider()
                            .padding(.leading, 52) // align to content edge past icon
                    }
                }
            }
        }
        .frame(maxHeight: 380)
    }
}
