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

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            iconView
            labelsView
            Spacer()
            trailingControl
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    // MARK: - Icon

    private var iconView: some View {
        Image(systemName: action.icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(iconColor)
            .frame(width: 28, height: 28)
            .background(iconBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - Labels

    private var labelsView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(action.title)
                .font(.system(size: 13, weight: .medium))
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

    // MARK: - Trailing Control

    @ViewBuilder
    private var trailingControl: some View {
        switch action.controlStyle {
        case .toggle:
            toggleControl

        case .momentaryButton(let label):
            Button(label) {
                Task { await viewModel.triggerAction(action.id, closePopover: closePopover) }
            }
            .buttonStyle(FluxaButtonStyle())
            .disabled(viewModel.isBusy)

        case .menu:
            audioDeviceMenu

        case .unavailable(let reason):
            Image(systemName: "minus.circle")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .help(reason)
        }
    }

    private var toggleControl: some View {
        let binding = Binding<Bool>(
            get: { viewModel.toggleStates[action.id.rawValue] ?? false },
            set: { _ in Task { await viewModel.toggleAction(action.id) } }
        )
        return Toggle("", isOn: binding)
            .labelsHidden()
            .tint(.blue)
            .disabled(viewModel.isBusy)
            .scaleEffect(0.85)
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
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(viewModel.audioOutput.outputDevices.isEmpty)
    }

    // MARK: - Styling

    private var isToggleOn: Bool {
        viewModel.toggleStates[action.id.rawValue] ?? false
    }

    private var iconColor: Color {
        switch action.controlStyle {
        case .unavailable:
            return .secondary
        case .toggle:
            return isToggleOn ? .blue : .secondary
        case .momentaryButton, .menu:
            return .primary
        }
    }

    private var iconBackground: Color {
        switch action.controlStyle {
        case .unavailable:
            return Color.secondary.opacity(0.08)
        case .toggle:
            return isToggleOn ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08)
        case .momentaryButton, .menu:
            return Color.secondary.opacity(0.08)
        }
    }
}

// MARK: - FluxaButtonStyle

/// Compact pill-shaped button style for momentary action triggers.
struct FluxaButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
