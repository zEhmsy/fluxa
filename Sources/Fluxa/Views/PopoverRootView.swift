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
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.refreshStates()
        }
        // Open the onboarding as a standalone Window (not a sheet) so it stays
        // visible when the user switches to the Shortcuts app to confirm import.
        .onChange(of: viewModel.isShowingFocusOnboarding) { _, showing in
            if showing { openWindow(id: "focus-onboarding") }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isShowingCustomize },
            set: { viewModel.isShowingCustomize = $0 }
        )) {
            CustomizeView()
                .environment(viewModel)
                .environment(settings)
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

            Text("Fluxa")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            // Loading indicator for async actions
            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .progressViewStyle(.circular)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    private func loadHeaderIcon() -> NSImage? {
        // Load the same switch icon from Bundle.module
        guard let url = Bundle.module.url(forResource: "fluxa", withExtension: "icns"),
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
