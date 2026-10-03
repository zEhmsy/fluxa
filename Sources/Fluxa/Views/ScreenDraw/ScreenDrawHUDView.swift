import FluxaCore
import SwiftUI

// MARK: - ScreenDrawHUDView

/// Floating toolbar rendered on screen during an active drawing session. Follows the selected
/// visual style: Classic uses the adaptive rounded surface, Cyber and Cyber Dark use the Control
/// Deck module with its cut corner and brand rail.
struct ScreenDrawHUDView: View {
    @Bindable var service: ScreenDrawService

    /// Transparent margin around the toolbar so its shadow is not clipped by the panel bounds.
    static let shadowMargin: CGFloat = 14

    /// Extra transparent room above the toolbar where hover hints appear.
    private static let hintHeadroom: CGFloat = 30

    private static let toolGroups: [[ScreenDrawTool]] = [
        [.pen, .highlighter],
        [.arrow, .line, .rectangle, .ellipse, .text],
        [.laserPointer, .spotlight, .eraser]
    ]

    private static let widthPresets: [Double] = [3, 6, 12]

    @Environment(\.fluxaVisualStyle) private var visualStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var isStyleExpanded = false

    private var style: ScreenDrawHUDStyle { ScreenDrawHUDStyle(visualStyle) }

    var body: some View {
        ZStack {
            if service.isHUDCollapsed {
                miniBar
            } else {
                ZStack {
                    bar(styleExpanded: true).hidden()
                    bar(styleExpanded: isStyleExpanded)
                }
            }
        }
        .padding(Self.shadowMargin)
        .padding(.top, Self.hintHeadroom)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: service.activeTool)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: service.selectedColor)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: service.strokeWidth)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isStyleExpanded)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: service.isHUDCollapsed)
    }

    private var miniBar: some View {
        HStack(spacing: 6) {
            grip

            // Active tool icon with color indicator
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                    service.isHUDCollapsed = false
                }
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: service.activeTool.sfSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(style.tint)
                        .frame(width: 24, height: 24)

                    Circle()
                        .fill(Color(red: service.selectedColor.red, green: service.selectedColor.green, blue: service.selectedColor.blue))
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                        .offset(x: -1, y: -1)
                }
            }
            .buttonStyle(.plain)
            .hudHint("Current: \(service.activeTool.displayName) — Click to expand", style: style)

            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                    service.isHUDCollapsed = false
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(style.secondaryText)
                    .frame(width: 18, height: 24)
            }
            .buttonStyle(.plain)
            .hudHint("Expand toolbar", style: style)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(style.surface, in: style.containerShape)
        .overlay { style.containerShape.stroke(style.border, lineWidth: 1) }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 10, y: 4)
    }

    private func bar(styleExpanded: Bool) -> some View {
        HStack(spacing: 6) {
            grip

            ForEach(Array(Self.toolGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 { groupDivider }
                HStack(spacing: 2) {
                    ForEach(group) { tool in toolButton(tool) }
                }
            }

            sectionDivider

            HStack(spacing: 1) {
                styleToggle(isExpanded: styleExpanded)

                if styleExpanded {
                    ForEach(ScreenDrawColor.presetPalette, id: \.self) { color in colorSwatch(color) }
                    groupDivider
                        .padding(.horizontal, 3)
                    ForEach(Self.widthPresets, id: \.self) { width in widthButton(width) }
                }
            }
            .opacity(usesInk ? 1 : 0.4)

            sectionDivider

            HStack(spacing: 2) {
                ScreenDrawHUDButton(
                    systemImage: "timer",
                    help: "Fade-out ink",
                    tint: style.fade,
                    isOn: service.activeMode == .disappearing,
                    style: style
                ) {
                    service.activeMode = service.activeMode == .disappearing ? .standard : .disappearing
                }

                ScreenDrawHUDButton(
                    systemImage: "cursorarrow.rays",
                    help: service.isClickThrough ? "Ghost mode active (hold ⌥)" : "Click-through to apps (hold ⌥)",
                    tint: style.ghost,
                    isOn: service.isClickThrough,
                    style: style
                ) {
                    service.isClickThrough.toggle()
                }

                ScreenDrawHUDButton(
                    systemImage: service.hideHUDFromScreenCapture ? "eye.slash" : "eye",
                    help: service.hideHUDFromScreenCapture
                        ? "Toolbar hidden from screen sharing"
                        : "Toolbar visible in screen sharing",
                    tint: style.tint,
                    isOn: service.hideHUDFromScreenCapture,
                    style: style
                ) {
                    service.hideHUDFromScreenCapture.toggle()
                }
            }

            sectionDivider

            HStack(spacing: 2) {
                ScreenDrawHUDButton(systemImage: "arrow.uturn.backward", help: "Undo (⌘Z)", style: style) {
                    service.undo()
                }
                .disabled(!service.history.canUndo)

                ScreenDrawHUDButton(systemImage: "arrow.uturn.forward", help: "Redo (⌘⇧Z)", style: style) {
                    service.redo()
                }
                .disabled(!service.history.canRedo)

                ScreenDrawHUDButton(
                    systemImage: service.isScreenshotCopied ? "checkmark" : "camera",
                    help: service.isScreenshotCopied ? "Screenshot copied!" : "Copy screenshot (⌘S)",
                    tint: style.tint,
                    isOn: service.isScreenshotCopied,
                    style: style
                ) {
                    service.captureAnnotatedScreenshot()
                }

                ScreenDrawHUDButton(systemImage: "trash", help: "Clear all (⌘K)", tint: style.critical, style: style) {
                    service.clear()
                }
                .disabled(service.history.strokes.isEmpty)
            }

            ScreenDrawHUDButton(
                systemImage: "chevron.down.circle",
                help: "Collapse toolbar",
                style: style
            ) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                    service.isHUDCollapsed = true
                }
            }

            exitButton
        }
        .padding(.leading, style.isCyber ? 0 : 6)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(style.surface, in: style.containerShape)
        .overlay { style.containerShape.stroke(style.border, lineWidth: 1) }
        .compositingGroup()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 10, y: 4)
    }

    /// Color and width only affect tools that leave ink on screen.
    private var usesInk: Bool { service.activeTool.isDrawingShape }

    // MARK: - Chrome

    @ViewBuilder
    private var grip: some View {
        if style.isCyber {
            ZStack {
                Rectangle()
                    .fill(style.palette.border)
                    .frame(width: 1.5)
                Rectangle()
                    .fill(style.palette.brandGradient)
                    .frame(width: 10, height: 10)
                    .rotationEffect(.degrees(45))
            }
            .frame(width: 26)
            .accessibilityHidden(true)
        } else {
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 3) {
                        Circle().frame(width: 2.5, height: 2.5)
                        Circle().frame(width: 2.5, height: 2.5)
                    }
                }
            }
            .foregroundStyle(style.tertiaryText)
            .frame(width: 12)
            .padding(.trailing, 2)
            .accessibilityHidden(true)
        }
    }

    private var groupDivider: some View {
        Rectangle()
            .fill(style.border.opacity(0.6))
            .frame(width: 1, height: 12)
            .accessibilityHidden(true)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(style.border)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }

    // MARK: - Controls

    private static func toolHelp(_ tool: ScreenDrawTool) -> String {
        switch tool {
        case .pen: return "Pen (1)"
        case .highlighter: return "Highlighter (2)"
        case .arrow: return "Arrow (3)"
        case .line: return "Line (4)"
        case .rectangle: return "Rectangle (5)"
        case .ellipse: return "Ellipse (6)"
        case .text: return "Text (7)"
        case .laserPointer: return "Laser (8)"
        case .spotlight: return "Spotlight (9)"
        case .eraser: return "Eraser (0)"
        }
    }

    private func toolButton(_ tool: ScreenDrawTool) -> some View {
        ScreenDrawHUDButton(
            systemImage: tool.sfSymbol,
            help: Self.toolHelp(tool),
            tint: style.tint,
            isOn: service.activeTool == tool,
            prominent: true,
            style: style
        ) {
            service.activeTool = tool
        }
    }

    /// Collapsed summary of the current ink: color swatch plus stroke weight. Clicking it reveals
    /// the palette and width presets inline.
    private func styleToggle(isExpanded: Bool) -> some View {
        let swatch = Color(
            red: service.selectedColor.red,
            green: service.selectedColor.green,
            blue: service.selectedColor.blue
        )
        let swatchShape = style.isCyber ? AnyShape(Rectangle()) : AnyShape(Circle())

        return Button {
            isStyleExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                swatchShape
                    .fill(swatch)
                    .overlay { swatchShape.stroke(style.border, lineWidth: 1) }
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(style.secondaryText)
                    .frame(width: 3 + service.strokeWidth * 0.6, height: 3 + service.strokeWidth * 0.6)
                    .frame(width: 11)
                Image(systemName: isExpanded ? "chevron.left" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(style.tertiaryText)
            }
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(isExpanded ? style.hover : .clear, in: style.controlShape(cut: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hudHint(isExpanded ? "Hide colors and stroke" : "Colors and stroke", style: style)
        .accessibilityLabel("Ink style, \(service.selectedColor.hex), \(Int(service.strokeWidth)) points")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private static func colorName(_ color: ScreenDrawColor) -> String {
        switch color {
        case .red:    return "Red (R)"
        case .orange: return "Orange (O)"
        case .yellow: return "Yellow (Y)"
        case .green:  return "Green (G)"
        case .cyan:   return "Cyan (B)"
        case .purple: return "Purple (P)"
        case .white:  return "White (W)"
        default:      return color.hex
        }
    }

    private func colorSwatch(_ color: ScreenDrawColor) -> some View {
        let isSelected = service.selectedColor == color
        let swatch = Color(red: color.red, green: color.green, blue: color.blue)

        return Button {
            service.selectedColor = color
            isStyleExpanded = false
        } label: {
            ZStack {
                (style.isCyber ? AnyShape(FluxCutShape(cut: 3)) : AnyShape(Circle()))
                    .stroke(style.primaryText.opacity(isSelected ? 0.85 : 0), lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                Group {
                    if style.isCyber {
                        Rectangle().fill(swatch)
                    } else {
                        Circle().fill(swatch)
                    }
                }
                .frame(width: isSelected ? 13 : 12, height: isSelected ? 13 : 12)
                .overlay {
                    if style.isCyber {
                        Rectangle().stroke(style.border, lineWidth: 1)
                    } else {
                        Circle().stroke(style.border, lineWidth: 1)
                    }
                }
            }
            .frame(width: 22, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hudHint(Self.colorName(color), style: style)
        .accessibilityLabel(Self.colorName(color))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func widthButton(_ width: Double) -> some View {
        let isSelected = abs(service.strokeWidth - width) < 0.5
        let diameter = 3 + width * 0.6
        let shortcut = (width == 3 ? " [" : width == 12 ? " ]" : "")

        return Button {
            service.strokeWidth = width
            isStyleExpanded = false
        } label: {
            Circle()
                .fill(isSelected ? style.tint : style.secondaryText)
                .frame(width: diameter, height: diameter)
                .frame(width: 20, height: 26)
                .background(isSelected ? style.tint.opacity(style.selectedFillOpacity) : .clear, in: style.controlShape(cut: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hudHint("Stroke \(Int(width)) pt\(shortcut)", style: style)
        .accessibilityLabel("Stroke width \(Int(width)) points")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var exitButton: some View {
        Button {
            service.deactivate()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(style.secondaryText)
                .frame(width: 24, height: 24)
                .background(style.hover, in: style.isCyber ? AnyShape(FluxCutShape(cut: 5)) : AnyShape(Circle()))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 2)
        .hudHint("Exit drawing (ESC)", style: style, alignment: .trailing)
        .accessibilityLabel("Exit drawing")
    }
}

// MARK: - ScreenDrawHUDButton

/// Icon button used across the HUD. `isOn` drives the selected/toggled look; `prominent` gives
/// Classic tool selection a filled accent, matching the in-popover tool grid.
private struct ScreenDrawHUDButton: View {
    let systemImage: String
    let help: String
    var tint: Color?
    var isOn = false
    var prominent = false
    let style: ScreenDrawHUDStyle
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                .foregroundStyle(foreground)
                .frame(width: 28, height: 26)
                .background(fill, in: style.controlShape(cut: 5))
                .overlay {
                    if isOn && style.isCyber {
                        style.controlShape(cut: 5).stroke((tint ?? style.tint).opacity(0.42), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .hudHint(help, style: style)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var resolvedTint: Color { tint ?? style.primaryText }

    private var foreground: Color {
        guard isEnabled else { return style.tertiaryText.opacity(0.6) }
        if isOn {
            return prominent && !style.isCyber ? .white : resolvedTint
        }
        return tint.map { isHovering ? $0 : style.primaryText.opacity(0.85) } ?? style.primaryText.opacity(0.85)
    }

    private var fill: Color {
        if isOn {
            return prominent && !style.isCyber
                ? FluxaTheme.accentFill
                : resolvedTint.opacity(style.selectedFillOpacity)
        }
        return isHovering && isEnabled ? style.hover : .clear
    }
}

// MARK: - Hover Hint

/// Small label shown above a HUD control after the pointer rests on it. Replaces `.help`, whose
/// system tooltip does not reliably appear over a non-activating panel while another app is
/// frontmost, and renders in the HUD's own theme.
private struct ScreenDrawHUDHintModifier: ViewModifier {
    let text: String
    let style: ScreenDrawHUDStyle
    let alignment: HorizontalAlignment

    private static let delay: Duration = .seconds(2)

    @State private var isShowing = false
    @State private var pending: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                pending?.cancel()
                guard hovering else {
                    isShowing = false
                    return
                }
                pending = Task { @MainActor in
                    try? await Task.sleep(for: Self.delay)
                    guard !Task.isCancelled else { return }
                    isShowing = true
                }
            }
            .onDisappear {
                pending?.cancel()
                isShowing = false
            }
            .overlay(alignment: Alignment(horizontal: alignment, vertical: .top)) {
                if isShowing {
                    label
                        .alignmentGuide(.top) { $0[.bottom] + 12 }
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isShowing)
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(style.primaryText)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(style.surface, in: style.controlShape(cut: 4))
            .overlay { style.controlShape(cut: 4).stroke(style.border, lineWidth: 1) }
            .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
            .accessibilityHidden(true)
    }
}

private extension View {
    func hudHint(
        _ text: String,
        style: ScreenDrawHUDStyle,
        alignment: HorizontalAlignment = .center
    ) -> some View {
        modifier(ScreenDrawHUDHintModifier(text: text, style: style, alignment: alignment))
    }
}

// MARK: - ScreenDrawHUDStyle

/// Resolves HUD colors and silhouettes from the active visual style, so every control reads from
/// one place and Classic/Cyber never mix within the toolbar.
private struct ScreenDrawHUDStyle {
    let isCyber: Bool
    let palette: ControlDeckPalette

    init(_ visualStyle: FluxaVisualStyle) {
        isCyber = visualStyle.isCyber
        palette = .resolve(visualStyle)
    }

    var surface: Color { isCyber ? palette.module : FluxaTheme.surface }
    var border: Color { isCyber ? palette.border : FluxaTheme.border }
    var hover: Color { isCyber ? palette.hover : FluxaTheme.hoverFill }
    var primaryText: Color { isCyber ? palette.primaryText : .primary }
    var secondaryText: Color { isCyber ? palette.secondaryText : .secondary }
    var tertiaryText: Color { isCyber ? palette.tertiaryText : Color.secondary.opacity(0.7) }

    var tint: Color { isCyber ? palette.actionColor(for: .screenDraw) : FluxaTheme.indigo }
    var fade: Color { isCyber ? palette.memory : FluxaTheme.orange }
    var ghost: Color { isCyber ? palette.temperature : FluxaTheme.teal }
    var critical: Color { isCyber ? palette.critical : FluxaTheme.red }

    var selectedFillOpacity: Double { isCyber ? (palette.isDark ? 0.16 : 0.11) : 0.16 }

    var containerShape: AnyShape {
        isCyber ? AnyShape(FluxCutShape(cut: 10)) : AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func controlShape(cut: CGFloat) -> AnyShape {
        isCyber ? AnyShape(FluxCutShape(cut: cut)) : AnyShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
