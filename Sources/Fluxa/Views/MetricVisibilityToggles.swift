import SwiftUI

// MARK: - MetricVisibilityToggles

/// The pair of controls that decide where one reading appears: in the popover strip, in the menu
/// bar, or both.
///
/// Two icon buttons rather than two switches. At the popover's 328pt width a row cannot carry two
/// labelled switches without the metric's own name losing its space, and the destinations are
/// inherently pictorial — a panel and a menu bar — so the glyphs say it faster than words would.
/// Each button spells itself out in its tooltip and its accessibility label.
struct MetricVisibilityToggles: View {

    @Binding var inPopover: Bool
    @Binding var inMenuBar: Bool

    /// Set when the menu bar is full, so the button explains why it won't turn on instead of
    /// failing silently.
    var menuBarBlockedReason: String?

    /// Set when this Mac cannot report the reading at all; disables both destinations.
    var isUnavailable = false

    var body: some View {
        HStack(spacing: 5) {
            button(
                isOn: $inPopover,
                symbol: "rectangle.inset.filled",
                label: "Show in popover",
                blockedReason: nil
            )
            button(
                isOn: $inMenuBar,
                symbol: "menubar.rectangle",
                label: "Show in menu bar",
                blockedReason: menuBarBlockedReason
            )
        }
    }

    private func button(
        isOn: Binding<Bool>,
        symbol: String,
        label: String,
        blockedReason: String?
    ) -> some View {
        // Blocked only bites when turning *on* — a reading already in the menu bar must always be
        // removable, otherwise a full menu bar would be impossible to get out of.
        let isBlocked = isUnavailable || (blockedReason != nil && !isOn.wrappedValue)

        return Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn.wrappedValue ? FluxaTheme.accent : Color.secondary)
                .frame(width: 26, height: 22)
                .background(
                    isOn.wrappedValue ? FluxaTheme.accent.opacity(0.12) : FluxaTheme.elevatedSurface,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isOn.wrappedValue ? FluxaTheme.accent.opacity(0.24) : FluxaTheme.border,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(isBlocked)
        .opacity(isBlocked ? 0.45 : 1)
        .help(isBlocked ? (blockedReason ?? "Not available on this Mac") : label)
        .accessibilityLabel(label)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }
}
