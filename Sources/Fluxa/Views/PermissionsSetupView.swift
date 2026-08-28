import SwiftUI

// MARK: - PermissionsSetupView

/// A standalone window: permission dialogs and System Settings must not dismiss the guide.
struct PermissionsSetupView: View {
    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.fluxaVisualStyle) private var visualStyle

    private var permissions: PermissionsService { viewModel.permissions }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }
    private var accent: Color { visualStyle == .classic ? FluxaTheme.accent : palette.brandBlue }
    private var isInstalled: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    var body: some View {
        VStack(spacing: 0) {
            FluxaPageHeader(
                title: permissions.showsWelcome ? "Welcome to Fluxa" : "Permissions & First Run",
                subtitle: permissions.showsWelcome ? "A guided start, on your terms" : "Enable only the features you want to use",
                systemImage: "checkmark.shield",
                tint: accent
            ) {
                if !permissions.showsWelcome {
                    Button("Refresh") { Task { await permissions.refresh() } }
                        .buttonStyle(FluxaButtonStyle())
                        .disabled(permissions.busyPermission != nil)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if permissions.showsWelcome {
                        welcomeContent
                    } else {
                        permissionContent
                    }
                    if let message = permissions.message {
                        Label(message, systemImage: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)
                    }
                }
                .padding(16)
            }

            FluxaPanelDivider(horizontalInset: 0)
            footer
        }
        .frame(width: 540, height: 640)
        .fluxaPanelSurface()
        .task { await permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await permissions.refresh() }
        }
        .onDisappear {
            settings.hasPresentedPermissionsSetup = true
        }
    }

    private var welcomeContent: some View {
        Group {
            FluxaToolCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your Mac, a little easier to control.")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Fluxa lives in the menu bar. Most controls work immediately; a few need your permission. "
                        + "This guide stays open while you approve them in macOS.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("No permission is requested just by opening this guide.", systemImage: "hand.raised")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            installationCard
            gatekeeperCard
        }
    }

    private var permissionContent: some View {
        Group {
            Text("Every permission is optional. Skipping one only disables the feature that needs it. "
                + "You can reopen this guide from Customize → Permissions & First Run.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PermissionSetupCard(
                title: "Accessibility", icon: "keyboard", feature: "Lock Keyboard",
                detail: "Blocks keyboard input until you turn the toggle off. The mouse remains usable.",
                status: permissions.accessibility, busy: false,
                actionTitle: "Enable…", action: permissions.requestAccessibility,
                settingsAction: { permissions.openSettings("Privacy_Accessibility") },
                requestsDisabled: !isInstalled || permissions.busyPermission != nil
            )
            PermissionSetupCard(
                title: "Automation", icon: "moon.lefthalf.filled", feature: "Dark Mode · System Events",
                detail: "Allows Fluxa to change system appearance. Setup only reads the current setting.",
                status: permissions.automation, busy: permissions.busyPermission == "automation",
                actionTitle: "Allow…", action: requestAutomation,
                settingsAction: { permissions.openSettings("Privacy_Automation") },
                requestsDisabled: !isInstalled || (permissions.busyPermission != nil && permissions.busyPermission != "automation")
            )
            PermissionSetupCard(
                title: "Bluetooth", icon: "headphones", feature: "Bluetooth Audio",
                detail: "Shows your paired headphones and lets you connect them. Setup does not scan or connect devices.",
                status: permissions.bluetooth, busy: false,
                actionTitle: "Allow…", action: permissions.requestBluetooth,
                settingsAction: { permissions.openSettings("Privacy_Bluetooth") },
                requestsDisabled: !isInstalled || permissions.busyPermission != nil
            )
            PermissionSetupCard(
                title: "Claude credentials", icon: "key", feature: "Optional · Agent Usage",
                detail: "Reads the login saved by Claude Code without changing it. If Keychain asks, choose Always Allow "
                    + "to trust this copy of Fluxa. A changed signing identity can require approval again.",
                status: claudeStatus, busy: permissions.busyPermission == "claude",
                actionTitle: "Connect Claude…", action: requestClaude,
                settingsAction: nil,
                requestsDisabled: !isInstalled || (permissions.busyPermission != nil && permissions.busyPermission != "claude")
            )

            FluxaToolCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Focus Mode", systemImage: "moon")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Focus uses two Shortcuts you create once. It does not need a privacy permission.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button(settings.focusModeOnboardingComplete ? "Review Focus Setup" : "Set Up Focus…", action: openFocusSetup)
                        .buttonStyle(FluxaButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Fluxa does not need Full Disk Access, Screen Recording or Microphone recording permission "
                + "for these controls. macOS owns permissions: this guide cannot grant them silently or make them permanent.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            installationCard
            gatekeeperCard
        }
    }

    private var installationCard: some View {
        FluxaToolCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(isInstalled ? "Running from Applications" : "Install in Applications first",
                      systemImage: isInstalled ? "checkmark.circle" : "externaldrive")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isInstalled ? FluxaTheme.green : FluxaTheme.orange)
                Text(isInstalled
                     ? "Keep a single installed copy so macOS permission settings refer to the app you actually open."
                     : "Quit this copy, drag Fluxa.app to Applications, then open it there before granting permissions. "
                        + "Avoid running from the DMG or Downloads.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Bundle.main.bundleURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var gatekeeperCard: some View {
        FluxaToolCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Gatekeeper is a separate first-open check", systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 13, weight: .semibold))
                Text("If macOS blocks Fluxa before it opens, this guide cannot run. After verifying that you downloaded "
                    + "the official release, try opening the installed app, then use System Settings → Privacy & Security "
                    + "→ Open Anyway if macOS offers it. This does not grant Accessibility or other permissions.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Apple's first-open guidance", destination: URL(string: "https://support.apple.com/102445")!)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            if permissions.showsWelcome {
                Button("Not Now", action: finish)
                    .buttonStyle(FluxaButtonStyle())
                Spacer()
                Button("Set Up Permissions") { permissions.showsWelcome = false }
                    .buttonStyle(FluxaPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Text("Your choices remain under macOS control.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: finish)
                    .buttonStyle(FluxaPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(permissions.busyPermission != nil)
            }
        }
        .padding(14)
    }

    private var claudeStatus: FluxaPermissionStatus {
        if viewModel.agentUsage.agentErrors["Claude"] != nil, permissions.claude == .granted {
            return .unavailable
        }
        if viewModel.agentUsage.agentErrors["Claude"] == nil,
           viewModel.agentUsage.metrics.contains(where: { $0.providerID == "claude" }) {
            return .granted
        }
        return permissions.claude
    }

    private func requestAutomation() {
        Task { await permissions.requestAutomation() }
    }

    private func requestClaude() {
        Task {
            await permissions.requestClaudeAccess()
            viewModel.agentUsage.refresh(force: true)
        }
    }

    private func openFocusSetup() {
        openWindow(id: "focus-onboarding")
        FluxaWindowPresenter.shared.bringToFront(id: "focus-onboarding")
    }

    private func finish() {
        settings.hasPresentedPermissionsSetup = true
        viewModel.refreshStates()
        dismissWindow(id: PermissionsService.windowID)
    }
}

private struct PermissionSetupCard: View {
    let title: String
    let icon: String
    let feature: String
    let detail: String
    let status: FluxaPermissionStatus
    let busy: Bool
    let actionTitle: String
    let action: () -> Void
    let settingsAction: (() -> Void)?
    var requestsDisabled = false

    var body: some View {
        FluxaToolCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Text(feature).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    FluxaStatusBadge(text: status.title, color: status == .granted ? FluxaTheme.green : FluxaTheme.orange)
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if status != .granted {
                        Button(actionTitle, action: action)
                            .buttonStyle(FluxaPrimaryButtonStyle())
                            .disabled(requestsDisabled || busy || status == .restricted)
                        if busy {
                            ProgressView().controlSize(.small)
                                .accessibilityLabel("Waiting for permission")
                        }
                    }
                    if let settingsAction {
                        Button("Open Settings", action: settingsAction)
                            .buttonStyle(FluxaButtonStyle())
                            .disabled(requestsDisabled || busy)
                    }
                }
            }
        }
    }
}
