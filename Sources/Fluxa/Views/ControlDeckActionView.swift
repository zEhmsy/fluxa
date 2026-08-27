import SwiftUI

// MARK: - ControlDeckActionView

/// Functional quick-action row rendered in the optional Control Deck dashboard.
/// The services and commands remain owned by `PopoverViewModel`; this view changes presentation
/// only and deliberately keeps native Button, Toggle and Menu semantics.
struct ControlDeckActionView: View {
    let action: QuickAction
    let palette: ControlDeckPalette
    var closePopover: (() -> Void)?

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var tint: Color { palette.actionColor(for: action.id) }
    private var isLoading: Bool { viewModel.busyActionID == action.id }

    var body: some View {
        HStack(spacing: 0) {
            ControlDeckRailCell(
                palette: palette,
                node: isToggleOn ? .filled(tint) : .none,
                segmentColor: isToggleOn ? tint : nil,
                showsBranch: isToggleOn
            )

            HStack(spacing: 9) {
                iconTile
                labels
                Spacer(minLength: 6)
                trailingControl
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .background(rowBackground)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(isToggleOn ? tint : Color.clear)
                    .frame(width: 2)
            }
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
            }
        }
    }

    private var iconTile: some View {
        ZStack {
            FluxCutShape(cut: 7)
                .fill(isToggleOn ? tint.opacity(0.20) : tint.opacity(0.09))
                .overlay {
                    FluxCutShape(cut: 7)
                        .stroke(tint.opacity(isToggleOn ? 0.42 : 0.22), lineWidth: 1)
                }

            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(tint)
                    .accessibilityLabel("Working")
            } else {
                Image(systemName: resolvedIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isUnavailable ? palette.tertiaryText : tint)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 22, height: 22)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(action.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isUnavailable ? palette.secondaryText : palette.primaryText)
                .lineLimit(1)

            if settings.showSubtitles {
                Text(statusCaption)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.25)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch action.controlStyle {
        case .toggle:
            toggleControl

        case .timedToggle:
            HStack(spacing: 7) {
                timerMenu
                toggleControl
            }

        case .momentaryButton(let label):
            Button(label) {
                Task { await viewModel.triggerAction(action.id, closePopover: closePopover) }
            }
            .buttonStyle(ControlDeckCutButtonStyle(tint: tint, palette: palette, reduceMotion: reduceMotion))
            .disabled(viewModel.isBusy)

        case .menu:
            if action.id == .bluetoothAudio {
                bluetoothDeviceMenu
            } else {
                audioDeviceMenu
            }

        case .unavailable(let reason):
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.tertiaryText)
                .help(reason)
                .accessibilityLabel(reason)
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
            .tint(tint)
            .disabled(viewModel.isBusy)
            .accessibilityLabel(action.title)
    }

    private var timerMenu: some View {
        Menu {
            Button("15 minutes") { viewModel.activateKeepAwake(for: 15 * 60) }
            Button("1 hour") { viewModel.activateKeepAwake(for: 60 * 60) }
            Button("4 hours") { viewModel.activateKeepAwake(for: 4 * 60 * 60) }
            Divider()
            Button("Indefinitely") { viewModel.activateKeepAwake(for: nil) }
        } label: {
            menuGlyph("timer")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(tint)
        .fixedSize()
        .disabled(viewModel.isBusy)
        .help("Keep awake for a limited time")
        .accessibilityLabel("Set Keep Awake duration")
    }

    private var bluetoothDeviceMenu: some View {
        Menu {
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
            menuGlyph("chevron.up.chevron.down")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(tint)
        .fixedSize()
        .disabled(viewModel.bluetoothAudio.devices.isEmpty || viewModel.isBusy)
        .accessibilityLabel("Choose Bluetooth audio device")
    }

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
            menuGlyph("chevron.up.chevron.down")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(tint)
        .fixedSize()
        .disabled(viewModel.audioOutput.outputDevices.isEmpty || viewModel.isBusy)
        .accessibilityLabel("Choose audio output")
    }

    private func menuGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 20, height: 18)
            .background(palette.recessed, in: FluxCutShape(cut: 5))
            .overlay { FluxCutShape(cut: 5).stroke(palette.border, lineWidth: 1) }
    }

    private var resolvedIcon: String {
        if isTogglable, isToggleOn, let activeIcon = action.activeIcon {
            return activeIcon
        }
        return action.icon
    }

    private var isTogglable: Bool {
        action.controlStyle == .toggle || action.controlStyle == .timedToggle
    }

    private var isToggleOn: Bool {
        isTogglable && (viewModel.toggleStates[action.id.rawValue] ?? false)
    }

    private var isUnavailable: Bool {
        if case .unavailable = action.controlStyle { return true }
        return false
    }

    private var statusCaption: String {
        if isLoading { return "WORKING…" }
        if isUnavailable { return "UNAVAILABLE" }

        switch action.controlStyle {
        case .toggle, .timedToggle:
            if isToggleOn {
                if action.id == .keepAwake,
                   let subtitle = viewModel.dynamicSubtitle(for: action.id) {
                    return subtitle.uppercased()
                }
                if action.id == .lockKeyboard {
                    return "LOCKED · USE TOGGLE TO UNLOCK"
                }
                return action.id == .keepAwake ? "ON · INDEFINITE" : "ON"
            }
            return "OFF"

        case .momentaryButton:
            return "READY"

        case .menu:
            return (viewModel.dynamicSubtitle(for: action.id) ?? action.subtitle ?? "READY").uppercased()

        case .unavailable:
            return "UNAVAILABLE"
        }
    }

    private var statusColor: Color {
        if isLoading || isToggleOn { return tint }
        return palette.tertiaryText
    }

    private var rowBackground: Color {
        if isToggleOn { return palette.module }
        if isHovering { return palette.hover }
        return palette.deck
    }
}
