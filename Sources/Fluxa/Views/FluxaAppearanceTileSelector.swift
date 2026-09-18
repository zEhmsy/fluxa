import SwiftUI

// MARK: - FluxaAppearanceTileSelector

/// Visual selector for Fluxa's appearance modes, presenting mini-card previews
/// inspired by macOS System Settings with faithful silhouettes for Classic and Cyber themes.
struct FluxaAppearanceTileSelector: View {
    @Binding var selection: FluxaVisualStyle

    @Environment(\.fluxaVisualStyle) private var currentStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FluxaVisualStyle.allCases) { style in
                AppearanceTile(
                    style: style,
                    isSelected: selection == style,
                    onSelect: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selection = style
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance selection")
    }
}

// MARK: - AppearanceTile

private struct AppearanceTile: View {
    let style: FluxaVisualStyle
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    private var tileBorderColor: Color {
        if isSelected {
            return FluxaTheme.accent
        } else if isHovered {
            return FluxaTheme.border.opacity(0.8)
        } else {
            return FluxaTheme.border.opacity(0.35)
        }
    }

    private var tileBorderWidth: CGFloat {
        isSelected ? 2 : 1
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if style.isCyber {
                            previewThumbnail
                                .clipShape(FluxCutShape(cut: 6))
                                .overlay {
                                    FluxCutShape(cut: 6)
                                        .stroke(tileBorderColor, lineWidth: tileBorderWidth)
                                }
                        } else {
                            previewThumbnail
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(tileBorderColor, lineWidth: tileBorderWidth)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .shadow(
                        color: isSelected ? FluxaTheme.accent.opacity(0.22) : .clear,
                        radius: 4,
                        x: 0,
                        y: 2
                    )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white, FluxaTheme.accent)
                            .padding(3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(style.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(style.title)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Thumbnail Previews

    @ViewBuilder
    private var previewThumbnail: some View {
        switch style {
        case .classic:
            autoThumbnail
        case .classicLight:
            classicLightThumbnail
        case .classicDark:
            classicDarkThumbnail
        case .cyber:
            cyberLightThumbnail
        case .cyberDark:
            cyberDarkThumbnail
        }
    }

    // MARK: 1. Auto (Split Half Light / Half Dark)

    private var autoThumbnail: some View {
        GeometryReader { geo in
            ZStack {
                HStack(spacing: 0) {
                    Color(red: 0.94, green: 0.95, blue: 0.97)
                        .frame(width: geo.size.width / 2)
                    Color(red: 0.11, green: 0.12, blue: 0.14)
                        .frame(width: geo.size.width / 2)
                }

                // Split mini cards
                HStack(spacing: 4) {
                    // Light side mini panel
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule()
                            .fill(Color(red: 0.15, green: 0.16, blue: 0.18).opacity(0.35))
                            .frame(width: 14, height: 3)
                        Capsule()
                            .fill(Color(red: 0.04, green: 0.36, blue: 0.79))
                            .frame(width: 18, height: 2.5)
                        Capsule()
                            .fill(Color(red: 0.80, green: 0.82, blue: 0.85))
                            .frame(width: 12, height: 2)
                    }
                    .padding(4)
                    .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                    // Dark side mini panel
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule()
                            .fill(Color.white.opacity(0.45))
                            .frame(width: 14, height: 3)
                        Capsule()
                            .fill(Color(red: 0.40, green: 0.68, blue: 1.0))
                            .frame(width: 18, height: 2.5)
                        Capsule()
                            .fill(Color(red: 0.25, green: 0.26, blue: 0.29))
                            .frame(width: 12, height: 2)
                    }
                    .padding(4)
                    .background(Color(red: 0.16, green: 0.17, blue: 0.20), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                // Center indicator badge
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .shadow(color: .black.opacity(0.2), radius: 2)
            }
        }
    }

    // MARK: 2. Classic Light

    private var classicLightThumbnail: some View {
        ZStack {
            Color(red: 0.94, green: 0.95, blue: 0.97)

            VStack(alignment: .leading, spacing: 4) {
                // Header bar
                HStack {
                    Capsule()
                        .fill(Color(red: 0.12, green: 0.13, blue: 0.15).opacity(0.55))
                        .frame(width: 22, height: 3.5)
                    Spacer()
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.orange)
                }

                // Mini content card
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(Color(red: 0.04, green: 0.36, blue: 0.79))
                            .frame(width: 3, height: 3)
                        Capsule()
                            .fill(Color(red: 0.04, green: 0.36, blue: 0.79))
                            .frame(width: 20, height: 2.5)
                    }
                    Capsule()
                        .fill(Color(red: 0.82, green: 0.84, blue: 0.88))
                        .frame(width: 28, height: 2)
                    Capsule()
                        .fill(Color(red: 0.20, green: 0.70, blue: 0.40))
                        .frame(width: 16, height: 2)
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                }
            }
            .padding(6)
        }
    }

    // MARK: 3. Classic Dark

    private var classicDarkThumbnail: some View {
        ZStack {
            Color(red: 0.10, green: 0.11, blue: 0.13)

            VStack(alignment: .leading, spacing: 4) {
                // Header bar
                HStack {
                    Capsule()
                        .fill(Color.white.opacity(0.70))
                        .frame(width: 22, height: 3.5)
                    Spacer()
                    Image(systemName: "moon.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Color(red: 0.45, green: 0.72, blue: 1.0))
                }

                // Mini content card
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(Color(red: 0.40, green: 0.68, blue: 1.0))
                            .frame(width: 3, height: 3)
                        Capsule()
                            .fill(Color(red: 0.40, green: 0.68, blue: 1.0))
                            .frame(width: 20, height: 2.5)
                    }
                    Capsule()
                        .fill(Color(red: 0.28, green: 0.29, blue: 0.33))
                        .frame(width: 28, height: 2)
                    Capsule()
                        .fill(Color(red: 0.35, green: 0.82, blue: 0.52))
                        .frame(width: 16, height: 2)
                }
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.16, green: 0.17, blue: 0.20), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                }
            }
            .padding(6)
        }
    }

    // MARK: 4. Cyber Light

    private var cyberLightThumbnail: some View {
        ZStack {
            Color(red: 0.90, green: 0.92, blue: 0.95)

            HStack(spacing: 4) {
                // Left accent neon rail
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.05, green: 0.45, blue: 0.92), Color(red: 0.45, green: 0.25, blue: 0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.5)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Capsule()
                            .fill(Color(red: 0.15, green: 0.16, blue: 0.20).opacity(0.7))
                            .frame(width: 20, height: 3)
                        Spacer()
                        Image(systemName: "cpu")
                            .font(.system(size: 7))
                            .foregroundStyle(Color(red: 0.05, green: 0.45, blue: 0.92))
                    }

                    // Cut module preview
                    VStack(alignment: .leading, spacing: 2.5) {
                        Capsule()
                            .fill(Color(red: 0.05, green: 0.45, blue: 0.92))
                            .frame(width: 16, height: 2.5)
                        Capsule()
                            .fill(Color(red: 0.78, green: 0.80, blue: 0.85))
                            .frame(width: 24, height: 2)
                    }
                    .padding(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.85), in: FluxCutShape(cut: 3))
                    .overlay {
                        FluxCutShape(cut: 3).stroke(Color(red: 0.05, green: 0.45, blue: 0.92).opacity(0.25), lineWidth: 0.5)
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: 5. Cyber Dark

    private var cyberDarkThumbnail: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.09)

            HStack(spacing: 4) {
                // Left neon rail
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.94, blue: 1.0), Color(red: 0.75, green: 0.35, blue: 1.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.5)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Capsule()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 20, height: 3)
                        Spacer()
                        Image(systemName: "cpu")
                            .font(.system(size: 7))
                            .foregroundStyle(Color(red: 0.0, green: 0.94, blue: 1.0))
                    }

                    // Cut module preview
                    VStack(alignment: .leading, spacing: 2.5) {
                        Capsule()
                            .fill(Color(red: 0.0, green: 0.94, blue: 1.0))
                            .frame(width: 16, height: 2.5)
                        Capsule()
                            .fill(Color(red: 0.25, green: 0.27, blue: 0.32))
                            .frame(width: 24, height: 2)
                    }
                    .padding(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.13, green: 0.14, blue: 0.18), in: FluxCutShape(cut: 3))
                    .overlay {
                        FluxCutShape(cut: 3).stroke(Color(red: 0.0, green: 0.94, blue: 1.0).opacity(0.35), lineWidth: 0.5)
                    }
                }
            }
            .padding(6)
        }
    }
}
