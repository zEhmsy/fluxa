import FluxaCore
import SwiftUI

// MARK: - ScreenDrawPanelView

/// In-popover dedicated configuration and control view for on-screen drawing and presentation tools.
struct ScreenDrawPanelView: View {

    static let panelWidth: CGFloat = 480

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.fluxaVisualStyle) private var visualStyle

    private var isCyber: Bool { visualStyle.isCyber }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }
    private var tint: Color { isCyber ? palette.actionColor(for: .screenDraw) : FluxaTheme.indigo }

    let onDone: () -> Void

    var body: some View {
        @Bindable var service = viewModel.screenDraw

        VStack(spacing: 0) {
            FluxaPageHeader(
                title: "Screen Draw",
                subtitle: "Presentation, annotation and screen focus tools",
                systemImage: "pencil.and.outline",
                tint: tint
            ) {
                Button("Done", action: onDone)
                    .buttonStyle(FluxaPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }

            SleekScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    // MARK: Status & Master Switch
                    sectionHeader("OVERLAY & CONTROLS")
                    FluxaToolCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(service.isActive ? "Drawing Mode Active" : "Drawing Mode Inactive")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(service.isActive ? "Draw anywhere on screen or use the floating toolbar" : "Toggle on to start drawing or press ⌘⇧D")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { service.isActive },
                                    set: { active in
                                        if active { service.activate() } else { service.deactivate() }
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .tint(tint)
                            }

                            Divider()

                            // Floating toolbar toggle
                            Toggle("Show Floating Toolbar on Screen", isOn: $service.showHUD)
                                .font(.system(size: 12))
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .tint(tint)

                            // Screen sharing visibility toggle
                            Toggle("Hide Toolbar in Screen Sharing", isOn: $service.hideHUDFromScreenCapture)
                                .font(.system(size: 12))
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .tint(tint)
                                .help("Hides the floating HUD toolbar from video calls (Meet, Zoom, Teams) and screen recordings while keeping your drawings visible")

                            // Click-Through toggle
                            Toggle("Click-Through Mode (Ghost)", isOn: $service.isClickThrough)
                                .font(.system(size: 12))
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .tint(isCyber ? palette.temperature : FluxaTheme.teal)
                                .help("Allows mouse clicks to pass through to underlying applications")
                        }
                    }

                    // MARK: Presentation Modes
                    sectionHeader("PRESENTATION MODE")
                    FluxaToolCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Mode", selection: $service.activeMode) {
                                ForEach(ScreenDrawMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)

                            if service.activeMode == .disappearing {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Fade-out duration:")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(Int(service.disappearingTimeout)) seconds")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    Slider(value: $service.disappearingTimeout, in: 1.0...10.0, step: 1.0)
                                        .tint(isCyber ? palette.memory : FluxaTheme.orange)
                                }
                                .padding(.top, 2)
                            } else if service.activeMode == .spotlight {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Spotlight beam size:")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(Int(service.spotlightRadius)) pt")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    Slider(value: $service.spotlightRadius, in: 80.0...250.0, step: 10.0)
                                        .tint(FluxaTheme.accent)
                                }
                                .padding(.top, 2)
                            }
                        }
                    }

                    // MARK: Active Tool Selection
                    sectionHeader("TOOLS")
                    FluxaToolCard {
                        VStack(spacing: 8) {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                                ForEach(ScreenDrawTool.allCases) { tool in
                                    toolTile(tool, service: service)
                                }
                            }
                        }
                    }

                    // MARK: Color Palette & Stroke Width
                    sectionHeader("STYLE & BRUSH")
                    FluxaToolCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Text("Color:")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                ForEach(ScreenDrawColor.presetPalette, id: \.self) { color in
                                    paletteCircle(color, service: service)
                                }
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Stroke Thickness:")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(service.strokeWidth)) pt")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                Slider(value: $service.strokeWidth, in: 2.0...24.0, step: 1.0)
                                    .tint(tint)
                            }
                        }
                    }

                    // MARK: Canvas Background
                    sectionHeader("BACKGROUND CANVAS")
                    FluxaToolCard {
                        Picker("Background", selection: $service.background) {
                            ForEach(ScreenDrawBackground.allCases) { bg in
                                Text(bg.displayName).tag(bg)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    // MARK: Quick Actions
                    sectionHeader("QUICK ACTIONS")
                    HStack(spacing: 10) {
                        Button {
                            service.undo()
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FluxaButtonStyle())
                        .disabled(!service.history.canUndo)

                        Button {
                            service.clear()
                        } label: {
                            Label("Clear Screen", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FluxaButtonStyle(tint: isCyber ? palette.critical : FluxaTheme.red))

                        Button {
                            service.activate()
                        } label: {
                            Label(service.isActive ? "Active" : "Start Draw", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FluxaButtonStyle(tint: tint))
                    }

                    // MARK: Shortcuts Tips
                    sectionHeader("KEYBOARD SHORTCUTS")
                    FluxaToolCard {
                        VStack(alignment: .leading, spacing: 5) {
                            shortcutRow(keys: "1 – 9, 0", description: "Select tools (Pen, Arrow, Text, Laser, etc.)")
                            shortcutRow(keys: "⇧ (Hold)", description: "Snap line/arrow to 45°, square/circle shapes")
                            shortcutRow(keys: "Scroll ⇅", description: "Resize spotlight radius live")
                            shortcutRow(keys: "R O Y G B P W", description: "Select palette colors (Red, Orange, etc.)")
                            shortcutRow(keys: "[  /  ]", description: "Decrease / increase stroke thickness")
                            shortcutRow(keys: "⌥ (Hold)", description: "Temporary click-through to apps")
                            shortcutRow(keys: "⌘ S", description: "Copy annotated screenshot to clipboard")
                            shortcutRow(keys: "⌘ Z / ⌘ ⇧ Z", description: "Undo / Redo (including Clear)")
                            shortcutRow(keys: "⌘ K", description: "Clear all annotations")
                            shortcutRow(keys: "ESC", description: "Exit drawing mode")
                            shortcutRow(keys: "⌘ ⇧ D", description: "Global hotkey to toggle overlay")
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(width: Self.panelWidth)
        .fluxaPanelSurface()
    }

    private func sectionHeader(_ title: String) -> some View {
        FluxaSectionLabel(title: title)
            .padding(.top, 4)
    }

    private func toolTile(_ tool: ScreenDrawTool, service: ScreenDrawService) -> some View {
        let isSelected = service.activeTool == tool
        let foreground: Color = isSelected
            ? (isCyber ? tint : .white)
            : (isCyber ? palette.primaryText : .primary)
        let fill: Color = isSelected
            ? (isCyber ? tint.opacity(palette.isDark ? 0.16 : 0.11) : FluxaTheme.accentFill)
            : (isCyber ? palette.recessed : FluxaTheme.elevatedSurface)
        let border: Color = isSelected
            ? (isCyber ? tint.opacity(0.42) : FluxaTheme.accentFill)
            : (isCyber ? palette.border : FluxaTheme.border)

        return Button {
            service.activeTool = tool
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.sfSymbol)
                    .font(.system(size: 13, weight: .medium))
                Text(tool.displayName)
                    .font(.system(size: 10))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .fluxaModuleChrome(fill: fill, border: border, cornerRadius: 8, cut: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func paletteCircle(_ color: ScreenDrawColor, service: ScreenDrawService) -> some View {
        let isSelected = service.selectedColor == color
        let swiftColor = Color(red: color.red, green: color.green, blue: color.blue)
        let border = isCyber ? palette.border : FluxaTheme.border
        let ring = isCyber ? palette.primaryText : Color.primary

        return Button {
            service.selectedColor = color
        } label: {
            ZStack {
                (isCyber ? AnyShape(FluxCutShape(cut: 4)) : AnyShape(Circle()))
                    .stroke(ring.opacity(isSelected ? 0.85 : 0), lineWidth: 1.5)
                    .frame(width: 24, height: 24)
                (isCyber ? AnyShape(Rectangle()) : AnyShape(Circle()))
                    .fill(swiftColor)
                    .overlay {
                        (isCyber ? AnyShape(Rectangle()) : AnyShape(Circle()))
                            .stroke(border, lineWidth: 1)
                    }
                    .frame(width: 16, height: 16)
            }
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(color.hex)
        .accessibilityLabel("Color \(color.hex)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func shortcutRow(keys: String, description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .fluxaModuleChrome(
                    fill: isCyber ? palette.recessed : Color.secondary.opacity(0.12),
                    border: isCyber ? palette.border : .clear,
                    cornerRadius: 4,
                    cut: 4
                )
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(isCyber ? palette.secondaryText : Color.secondary)
            Spacer()
        }
    }
}
