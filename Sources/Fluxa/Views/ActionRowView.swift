import SwiftUI

// MARK: - ActionRowView

/// A single row in the Fluxa popover panel.
/// Renders the appropriate trailing control based on the action's ControlStyle:
///   - .toggle          → SwiftUI Toggle
///   - .momentaryButton → pill-shaped Button
///   - .menu            → SwiftUI Menu (inline device picker for audio output)
///   - .unavailable     → greyed minus indicator with tooltip
struct ActionRowView: View {

    let action: QuickAction
    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings

    /// Callback for momentary actions that need to close the popover first.
    var closePopover: (() -> Void)?

    @State private var isHovering = false
    @State private var pendingKill: RunningProcessInfo?

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            iconView
            labelsView
            Spacer(minLength: 8)
            trailingControl
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: FluxaTheme.rowCornerRadius, style: .continuous)
                .fill(isHovering ? FluxaTheme.hoverFill : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: FluxaTheme.rowCornerRadius, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    // MARK: - Icon

    /// Resolves the correct SF Symbol name based on the action's current state.
    /// For toggles: returns activeIcon when on, icon when off.
    /// For other control styles: always returns the base icon.
    private var resolvedIcon: String {
        if action.id == .killProcess && pendingKill != nil {
            return "exclamationmark.triangle.fill"
        }
        if isTogglable, isToggleOn, let active = action.activeIcon {
            return active
        }
        return action.icon
    }

    /// True for both plain and timed toggles.
    private var isTogglable: Bool {
        action.controlStyle == .toggle || action.controlStyle == .timedToggle
    }

    private var iconView: some View {
        Image(systemName: resolvedIcon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(iconColor)
            .frame(width: 30, height: 30)
            .background(iconBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(iconColor.opacity(isToggleOn ? 0.38 : 0.18), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.15), value: isToggleOn)
            .accessibilityHidden(true)
    }

    // MARK: - Labels

    private var labelsView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let pending = pendingKill, action.id == .killProcess {
                Text("Quit \(pending.name)?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FluxaTheme.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Force-quit if not exiting in 2s")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(action.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if settings.showSubtitles {
                    // Dynamic subtitle takes precedence over catalog subtitle
                    let subtitle = viewModel.dynamicSubtitle(for: action.id) ?? action.subtitle
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Trailing Control

    @ViewBuilder
    private var trailingControl: some View {
        if let pending = pendingKill, action.id == .killProcess {
            HStack(spacing: 6) {
                Button("Quit") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        confirmTermination(of: pending)
                    }
                }
                .buttonStyle(FluxaButtonStyle(tint: FluxaTheme.red))

                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        pendingKill = nil
                    }
                }
                .buttonStyle(FluxaButtonStyle(tint: .secondary))
            }
            .fixedSize(horizontal: true, vertical: false)
        } else {
            switch action.controlStyle {
            case .toggle:
                toggleControl

            case .timedToggle:
                HStack(spacing: 8) {
                    timerMenu
                    toggleControl
                }

            case .momentaryButton(let label):
                Button(label) {
                    Task { await viewModel.triggerAction(action.id, closePopover: closePopover) }
                }
                .buttonStyle(FluxaButtonStyle(tint: action.tint))
                .disabled(viewModel.isBusy)

            case .menu:
                if action.id == .bluetoothAudio {
                    bluetoothDeviceMenu
                } else if action.id == .killProcess {
                    processKillerMenu
                } else {
                    audioDeviceMenu
                }

            case .unavailable(let reason):
                Image(systemName: "minus.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .help(reason)
            }
        }
    }

    private var toggleControl: some View {
        let binding = Binding<Bool>(
            get: { viewModel.toggleStates[action.id.rawValue] ?? false },
            set: { _ in Task { await viewModel.toggleAction(action.id) } }
        )
        return Toggle("", isOn: binding)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(action.tint)
            .disabled(viewModel.isBusy)
    }

    /// Timer menu for timed activation (Keep Awake: 15 min / 1 h / 4 h).
    private var timerMenu: some View {
        Menu {
            Button("15 minutes") { viewModel.activateKeepAwake(for: 15 * 60) }
            Button("1 hour") { viewModel.activateKeepAwake(for: 60 * 60) }
            Button("4 hours") { viewModel.activateKeepAwake(for: 4 * 60 * 60) }
            Divider()
            Button("Indefinitely") { viewModel.activateKeepAwake(for: nil) }
        } label: {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FluxaTheme.accent)
                .frame(width: 24, height: 22)
                .background(FluxaTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(FluxaTheme.border, lineWidth: 1)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(viewModel.isBusy)
        .help("Keep awake for a limited time")
        .accessibilityLabel("Set Keep Awake duration")
    }

    /// Inline Menu listing paired Bluetooth audio devices; selecting one
    /// connects it (or disconnects it when already connected).
    private var bluetoothDeviceMenu: some View {
        Menu {
            if !viewModel.bluetoothAudio.hasPermission {
                Button("Set Up Bluetooth…") { viewModel.isShowingPermissionsSetup = true }
            } else if viewModel.bluetoothAudio.devices.isEmpty {
                Text("No paired audio devices")
            }
            ForEach(viewModel.bluetoothAudio.devices) { device in
                Button {
                    Task { await viewModel.toggleBluetoothDevice(device.id) }
                } label: {
                    HStack {
                        Text(device.name)
                        if device.isConnected {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FluxaTheme.accent)
            }
            .frame(width: 24, height: 22)
            .background(FluxaTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(FluxaTheme.border, lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(viewModel.isBusy)
        .accessibilityLabel("Choose Bluetooth audio device")
    }

    /// Inline Menu for audio output device selection.
    private var audioDeviceMenu: some View {
        Menu {
            ForEach(viewModel.audioOutput.outputDevices) { device in
                Button {
                    viewModel.selectAudioDevice(device)
                } label: {
                    HStack {
                        Text(device.name)
                        if device.id == viewModel.audioOutput.currentDevice?.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FluxaTheme.accent)
            }
            .frame(width: 24, height: 22)
            .background(FluxaTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(FluxaTheme.border, lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(viewModel.audioOutput.outputDevices.isEmpty)
        .accessibilityLabel("Choose audio output")
    }

    /// Inline Menu listing regular GUI applications; selection is confirmed before termination.
    private var processKillerMenu: some View {
        Menu {
            ForEach(viewModel.processKiller.runningProcesses) { process in
                Button(process.name) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        pendingKill = process
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FluxaTheme.accent)
            }
            .frame(width: 24, height: 22)
            .background(FluxaTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(FluxaTheme.border, lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(viewModel.processKiller.runningProcesses.isEmpty || viewModel.isBusy)
        .accessibilityLabel("Choose an app to quit")
    }

    private func confirmTermination(of process: RunningProcessInfo) {
        pendingKill = nil
        viewModel.processKiller.terminate(process)
    }

    // MARK: - Styling

    private var isToggleOn: Bool {
        viewModel.toggleStates[action.id.rawValue] ?? false
    }

    private var iconColor: Color {
        if case .unavailable = action.controlStyle { return .secondary }
        return action.tint
    }

    private var iconBackground: AnyShapeStyle {
        switch action.controlStyle {
        case .unavailable:
            return AnyShapeStyle(FluxaTheme.elevatedSurface)
        case .toggle, .timedToggle:
            return isToggleOn
                ? AnyShapeStyle(action.tint.opacity(0.22))
                : AnyShapeStyle(action.tint.opacity(0.10))
        case .momentaryButton, .menu:
            return AnyShapeStyle(action.tint.opacity(0.10))
        }
    }
}

// MARK: - FluxaButtonStyle

/// Compact pill-shaped button style for momentary action triggers.
struct FluxaButtonStyle: ButtonStyle {
    var tint: Color = FluxaTheme.accent

    @Environment(\.fluxaVisualStyle) private var visualStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCyber: Bool { visualStyle != .classic }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                if isCyber {
                    FluxCutShape(cut: 6)
                        .fill(configuration.isPressed ? palette.pressed : tint.opacity(0.11))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(configuration.isPressed ? 0.22 : 0.12))
                }
            }
            .overlay {
                if isCyber {
                    FluxCutShape(cut: 6).stroke(tint.opacity(0.36), lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(tint.opacity(0.28), lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
