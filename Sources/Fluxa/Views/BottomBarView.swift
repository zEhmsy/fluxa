import SwiftUI

// MARK: - BottomBarView

/// The bottom section of the Fluxa popover with Customize and Quit buttons.
struct BottomBarView: View {

    @Environment(PopoverViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 0) {
            // Customize button
            Button {
                viewModel.isShowingCustomize = true
            } label: {
                Label("Customize", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(BottomBarButtonStyle(alignment: .leading))

            Spacer()

            // Quit button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit Fluxa")
                    .font(.system(size: 12))
            }
            .buttonStyle(BottomBarButtonStyle(alignment: .trailing))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

// MARK: - BottomBarButtonStyle

struct BottomBarButtonStyle: ButtonStyle {
    let alignment: HorizontalAlignment

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
