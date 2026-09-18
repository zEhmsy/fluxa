import SwiftUI

// MARK: - ActionListView

/// Scrollable list of action rows, driven by the user's ordering and visibility preferences.
struct ActionListView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(PopoverViewModel.self) private var viewModel

    /// Passed through to each row so momentary actions can close the popover.
    var closePopover: (() -> Void)?

    private var rowHeight: CGFloat {
        settings.showSubtitles ? 46 : 44
    }

    var body: some View {
        let actions = settings.visibleActions

        VStack(alignment: .leading, spacing: 7) {
            FluxaSectionLabel(title: "Quick actions", trailing: "\(actions.count)")

            Group {
                if actions.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(FluxaTheme.accent)
                        Text("No visible actions")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(12)
                } else if actions.count > 8 {
                    SleekScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(actions) { action in
                                ActionRowView(action: action, closePopover: closePopover)
                            }
                        }
                    }
                    .frame(height: 8 * rowHeight + 7)
                } else {
                    VStack(spacing: 1) {
                        ForEach(actions) { action in
                            ActionRowView(action: action, closePopover: closePopover)
                        }
                    }
                }
            }
            .padding(4)
            .background(FluxaTheme.surface, in: RoundedRectangle(cornerRadius: FluxaTheme.panelCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: FluxaTheme.panelCornerRadius, style: .continuous)
                    .stroke(FluxaTheme.border, lineWidth: 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}
