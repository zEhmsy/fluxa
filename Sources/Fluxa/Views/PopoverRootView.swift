import SwiftUI

// MARK: - PopoverRootView

/// Root container view rendered inside the MenuBarExtra window.
/// Composes the header, action list, error banner, and bottom bar.
struct PopoverRootView: View {

    private enum Screen {
        case dashboard
        case customize
        case info
    }

    /// Cached once rather than decoded every time SwiftUI recomputes the header.
    private static let headerIcon: NSImage? = {
        guard let url = Bundle.fluxaResources.url(forResource: "menu-icon", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }()

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow

    @State private var screen = Screen.dashboard

    /// Called to close the popover (injected from MenuBarExtra scene).
    var closePopover: (() -> Void)?

    var body: some View {
        ZStack(alignment: .top) {
            switch screen {
            case .dashboard:
                dashboard
                    .transition(.move(edge: .leading))
            case .customize:
                CustomizeView(onDone: closeCustomize)
                    .transition(.move(edge: .trailing))
            case .info:
                InfoView(onDone: closeInfo)
                    .environment(viewModel)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(width: FluxaTheme.panelWidth)
        .background(FluxaTheme.panelBackground)
        .clipped()
        .onAppear {
            viewModel.refreshStates()
            // Capture the MenuBarExtra window so the global hotkey can toggle it.
            if viewModel.menuBarWindow == nil {
                viewModel.menuBarWindow = NSApp.keyWindow
            }
        }
        // Standalone windows remain coordinated even while Customize replaces the dashboard.
        .onChange(of: viewModel.isShowingFocusOnboarding) { _, showing in
            if showing { presentWindow(id: "focus-onboarding") }
        }
        .onChange(of: viewModel.isShowingLidAngle) { _, showing in
            if showing {
                presentWindow(id: "lid-angle")
                viewModel.isShowingLidAngle = false
            }
        }
        .onChange(of: viewModel.isShowingTrackpadScale) { _, showing in
            if showing {
                presentWindow(id: "trackpad-scale")
                viewModel.isShowingTrackpadScale = false
            }
        }
        .onChange(of: viewModel.isShowingAgentUsage) { _, showing in
            if showing {
                presentWindow(id: "agent-usage")
                viewModel.isShowingAgentUsage = false
            }
        }
        .onChange(of: viewModel.isShowingSystemStats) { _, showing in
            if showing {
                presentWindow(id: "system-stats")
                viewModel.isShowingSystemStats = false
            }
        }
    }

    /// Selects the complete dashboard composition. Keeping Classic as its own subtree prevents the
    /// optional Control Deck themes from changing the interface existing users already have.
    @ViewBuilder
    private var dashboard: some View {
        switch settings.visualStyle {
        case .classic:
            classicDashboard
        case .cyber, .cyberDark:
            ControlDeckDashboardView(
                style: settings.visualStyle,
                onCustomize: showCustomize,
                onAbout: showInfo,
                closePopover: closePopover
            )
            .environment(viewModel)
            .environment(settings)
        }
    }

    /// The original menu-bar screen. Customize is pushed inside the same MenuBarExtra window, so
    /// opening it never transfers focus to a new window.
    private var classicDashboard: some View {
        VStack(spacing: 0) {
            // MARK: Header
            headerView

            // MARK: System Stats Strip (only when the user pinned something in Customize)
            if SystemStatsStripView.hasContent(viewModel: viewModel, settings: settings) {
                SystemStatsStripView(closePopover: closePopover)
                    .environment(viewModel)
                    .environment(settings)
            }

            // MARK: Agent Usage Strip (only when the user pinned something in Customize)
            if AgentUsageStripView.hasContent(viewModel: viewModel, settings: settings) {
                AgentUsageStripView(closePopover: closePopover)
                    .environment(viewModel)
                    .environment(settings)
            }

            // MARK: Error Banner (conditional)
            if let error = viewModel.errorMessage {
                errorBanner(message: error)
            }

            // MARK: Action List
            ActionListView(closePopover: closePopover)
                .environment(viewModel)
                .environment(settings)

            // MARK: Bottom Bar
            BottomBarView(onCustomize: showCustomize, onAbout: showInfo)
        }
        .frame(width: FluxaTheme.panelWidth)
        .background(FluxaTheme.panelBackground)
    }

    // MARK: - Navigation

    private func presentWindow(id: String) {
        // MenuBarExtra windows do not always dismiss when another window from the same accessory
        // app becomes key. Hide it explicitly so it cannot overlap the tool window it just opened.
        viewModel.menuBarWindow?.orderOut(nil)
        openWindow(id: id)
        FluxaWindowPresenter.shared.bringToFront(id: id)
    }

    private func showCustomize() {
        guard screen != .customize else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            screen = .customize
        }
    }

    private func closeCustomize() {
        guard screen != .dashboard else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            screen = .dashboard
        }
    }

    private func showInfo() {
        guard screen != .info else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            screen = .info
        }
    }

    private func closeInfo() {
        guard screen != .dashboard else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            screen = .dashboard
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 10) {
            brandMark

            VStack(alignment: .leading, spacing: 1) {
                Text("Fluxa")
                    .font(.system(size: 14, weight: .semibold))
                Text("System controls")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Loading indicator for async actions
            if viewModel.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .progressViewStyle(.circular)
                    .tint(FluxaTheme.accent)
                    .accessibilityLabel("Working")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(FluxaTheme.surface)
        .overlay(alignment: .bottom) {
            FluxaPanelDivider(horizontalInset: 0)
        }
    }

    @ViewBuilder
    private var brandMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(FluxaTheme.accentFill)

            if let image = Self.headerIcon {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "togglepower")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 32, height: 32)
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: FluxaTheme.accentFill.opacity(0.24), radius: 5, y: 2)
        .accessibilityHidden(true)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(FluxaTheme.orange)

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
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(FluxaTheme.warningFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(FluxaTheme.warningBorder, lineWidth: 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }
}
