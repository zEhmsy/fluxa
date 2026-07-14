import SwiftUI

// MARK: - PopoverRootView

/// Root container view rendered inside the MenuBarExtra window.
/// Composes the header, action list, error banner, and bottom bar.
struct PopoverRootView: View {

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow

    /// Called to close the popover (injected from MenuBarExtra scene).
    var closePopover: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            headerView

            Divider()

            // MARK: Error Banner (conditional)
            if let error = viewModel.errorMessage {
                errorBanner(message: error)
                Divider()
            }

            // MARK: Action List
            ActionListView(closePopover: closePopover)
                .environment(viewModel)
                .environment(settings)

            Divider()

            // MARK: Bottom Bar
            BottomBarView()
                .environment(viewModel)
        }
        .frame(width: 304)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.refreshStates()
            // Capture the MenuBarExtra window so the global hotkey can toggle it.
            if viewModel.menuBarWindow == nil {
                viewModel.menuBarWindow = NSApp.keyWindow
            }
        }
        // Open the onboarding as a standalone Window (not a sheet) so it stays
        // visible when the user switches to the Shortcuts app to confirm import.
        .onChange(of: viewModel.isShowingFocusOnboarding) { _, showing in
            if showing { openWindow(id: "focus-onboarding") }
        }
        .onChange(of: viewModel.isShowingLidAngle) { _, showing in
            if showing {
                openWindow(id: "lid-angle")
                viewModel.isShowingLidAngle = false
            }
        }
        .onChange(of: viewModel.isShowingCustomize) { _, showing in
            if showing {
                openWindow(id: "customize")
                // Bring the window to front — the app is a menu bar accessory.
                NSApp.activate(ignoringOtherApps: true)
                viewModel.isShowingCustomize = false
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 8) {
            // Load the switch icon from the app bundle
            if let image = loadHeaderIcon() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Fluxa")
                    .font(.system(size: 13, weight: .semibold))
                Text("Quick actions")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Loading indicator for async actions
            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .progressViewStyle(.circular)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func loadHeaderIcon() -> NSImage? {
        // Same switch icon used in the menu bar
        guard let url = Bundle.fluxaResources.url(forResource: "fluxa", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}
