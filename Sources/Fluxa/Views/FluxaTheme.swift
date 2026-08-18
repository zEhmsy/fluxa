import AppKit
import SwiftUI

// MARK: - FluxaTheme

/// Shared visual language for the menu-bar panel. Colors are adaptive so the same hierarchy and
/// contrast survive both Aqua appearances instead of relying on low-opacity black/white overlays.
enum FluxaTheme {
    static let panelWidth: CGFloat = 328
    static let panelCornerRadius: CGFloat = 12
    static let rowCornerRadius: CGFloat = 9

    static let accent = adaptive(
        light: color(10, 91, 201),
        dark: color(102, 174, 255)
    )

    /// Darker than `accent` in Dark Mode so white text remains legible on filled controls.
    static let accentFill = adaptive(
        light: color(10, 91, 201),
        dark: color(23, 91, 166)
    )

    static let panelBackground = adaptive(
        light: color(246, 247, 249),
        dark: color(24, 25, 28)
    )

    static let surface = adaptive(
        light: color(255, 255, 255),
        dark: color(36, 37, 41)
    )

    static let elevatedSurface = adaptive(
        light: color(250, 251, 252),
        dark: color(43, 44, 49)
    )

    static let border = adaptive(
        light: color(216, 220, 227),
        dark: color(61, 63, 70)
    )

    static let hoverFill = adaptive(
        light: color(236, 241, 248),
        dark: color(50, 53, 60)
    )

    static let pressedFill = adaptive(
        light: color(224, 232, 243),
        dark: color(58, 62, 71)
    )

    static let warningFill = adaptive(
        light: color(255, 246, 224),
        dark: color(66, 48, 22)
    )

    static let warningBorder = adaptive(
        light: color(224, 174, 72),
        dark: color(157, 112, 42)
    )

    // Accessible semantic accents. Light variants are dark enough on white; Dark variants are
    // brighter for clear icon and switch contrast on dark surfaces.
    static let orange = adaptive(light: color(167, 70, 0), dark: color(255, 167, 72))
    static let amber = adaptive(light: color(132, 84, 0), dark: color(255, 201, 82))
    static let teal = adaptive(light: color(0, 112, 120), dark: color(85, 211, 218))
    static let mint = adaptive(light: color(19, 117, 83), dark: color(84, 218, 166))
    static let brown = adaptive(light: color(116, 76, 50), dark: color(205, 154, 118))
    static let purple = adaptive(light: color(112, 56, 176), dark: color(190, 132, 255))
    static let cyan = adaptive(light: color(0, 105, 143), dark: color(84, 198, 235))
    static let red = adaptive(light: color(185, 48, 45), dark: color(255, 112, 107))
    static let indigo = adaptive(light: color(69, 66, 155), dark: color(150, 146, 255))
    static let blue = adaptive(light: color(10, 91, 201), dark: color(102, 174, 255))
    static let pink = adaptive(light: color(171, 49, 115), dark: color(255, 126, 192))
    static let green = adaptive(light: color(20, 120, 68), dark: color(89, 211, 133))

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

// MARK: - Shared Components

struct FluxaPanelDivider: View {
    var horizontalInset: CGFloat = 12

    var body: some View {
        Rectangle()
            .fill(FluxaTheme.border)
            .frame(height: 1)
            .padding(.horizontal, horizontalInset)
            .accessibilityHidden(true)
    }
}

struct FluxaSectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FluxaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                FluxaTheme.accentFill.opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Tool Window Components

struct FluxaToolHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tint.opacity(0.24), lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

struct FluxaToolCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(FluxaTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FluxaTheme.border, lineWidth: 1)
            }
    }
}

struct FluxaStatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.11), in: Capsule())
        .overlay {
            Capsule()
                .stroke(color.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
