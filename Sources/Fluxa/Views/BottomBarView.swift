import SwiftUI

// MARK: - BottomBarView

/// The bottom section of the Fluxa popover with Customize and Quit buttons.
struct BottomBarView: View {

    let onCustomize: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Customize button
            Button(action: onCustomize) {
                Label("Customize", systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(BottomBarButtonStyle(tint: FluxaTheme.accent, isEmphasized: true))

            Spacer()

            // Quit button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(BottomBarButtonStyle(tint: Color.secondary, isEmphasized: false))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(FluxaTheme.surface)
        .overlay(alignment: .top) {
            FluxaPanelDivider(horizontalInset: 0)
        }
    }
}

// MARK: - BottomBarButtonStyle

struct BottomBarButtonStyle: ButtonStyle {
    let tint: Color
    let isEmphasized: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay {
                if isEmphasized {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(tint.opacity(0.24), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isEmphasized {
            return tint.opacity(isPressed ? 0.18 : 0.10)
        }
        return isPressed ? FluxaTheme.pressedFill : Color.clear
    }
}
