import SwiftUI

// MARK: - LidAngleWindowView

/// Dedicated window that shows the MacBook lid angle as an animated side-profile diagram.
struct LidAngleWindowView: View {

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(\.fluxaVisualStyle) private var visualStyle

    /// Smoothed angle used for animation — updated from the monitor via withAnimation.
    @State private var displayAngle: Double = 90

    private var monitor: LidAngleMonitor { viewModel.lidAngleMonitor }
    private var isCyber: Bool { visualStyle != .classic }

    var body: some View {
        VStack(spacing: 14) {
            FluxaToolHeader(
                title: "Lid Angle",
                subtitle: "Live hinge sensor",
                systemImage: "laptopcomputer",
                tint: FluxaTheme.blue
            )

            if monitor.isAvailable {
                FluxaToolCard {
                    VStack(spacing: 4) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(format: "%.1f°", displayAngle))
                                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .foregroundStyle(angleColor)

                                Text(angleDescription)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            FluxaStatusBadge(
                                text: displayAngle < 5 ? "CLOSED" : "LIVE",
                                color: statusColor
                            )
                        }

                        MacBookProfileView(angle: displayAngle)
                            .frame(height: 190)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("MacBook lid angle")
                            .accessibilityValue("\(String(format: "%.1f", displayAngle)) degrees")
                    }
                }
            } else {
                FluxaToolCard {
                    unavailableView
                        .frame(maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(width: 390, height: 360)
        .fluxaPanelSurface()
        .onAppear {
            monitor.startPolling()
            displayAngle = monitor.angleDegrees
        }
        .onDisappear {
            monitor.stopPolling()
        }
        .onChange(of: monitor.angleDegrees) { _, newAngle in
            // interactiveSpring gives a natural "physical" feel as the screen moves
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.7)) {
                displayAngle = newAngle
            }
        }
    }

    // MARK: - Presentation

    private var angleColor: Color {
        displayAngle > 180 ? FluxaTheme.orange : FluxaTheme.blue
    }

    private var statusColor: Color {
        displayAngle < 5 ? Color.secondary : FluxaTheme.green
    }

    private var angleDescription: String {
        switch displayAngle {
        case ..<5: return "Lid closed"
        case ..<70: return "Low viewing angle"
        case ..<125: return "Comfortable viewing angle"
        case ...180: return "Wide open"
        default: return "Beyond flat"
        }
    }

    // MARK: - Subviews

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(FluxaTheme.orange)
                .frame(width: 56, height: 56)
                .fluxaModuleChrome(
                    fill: FluxaTheme.orange.opacity(0.10),
                    border: FluxaTheme.orange.opacity(isCyber ? 0.32 : 0),
                    cornerRadius: 14,
                    cut: 11
                )
            Text("Lid Angle Not Available")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text("This sensor is only present on MacBook models.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - MacBookProfileView

/// Custom Canvas that draws a side-profile MacBook silhouette:
/// - A fixed horizontal base line (top case / keyboard deck).
/// - A screen line that rotates from the hinge based on `angle`.
/// - A goniometer arc between the two lines.
struct MacBookProfileView: View {

    /// Lid angle in degrees (0 = closed, 90 = upright, 180 = fully flat open).
    let angle: Double

    @Environment(\.fluxaVisualStyle) private var visualStyle

    // Design constants
    private var isCyber: Bool { visualStyle != .classic }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }
    private var baseColor: Color { isCyber ? palette.secondaryText : Color.secondary }
    private var screenColor: Color { isCyber ? palette.primaryText : Color.primary }
    private var arcColor: Color { isCyber ? palette.brandBlue : FluxaTheme.blue }
    private var overColor: Color { isCyber ? palette.warning : FluxaTheme.orange }

    var body: some View {
        Canvas { ctx, size in
            let hinge = CGPoint(x: size.width * 0.32, y: size.height * 0.68)
            let baseLen:   CGFloat = size.width  * 0.54
            let screenLen: CGFloat = size.height * 0.52
            let arcRadius: CGFloat = 52
            let lineWidth: CGFloat = 3

            // ── 1. Base line (top case, horizontal, going right) ──────────────
            let baseEnd = CGPoint(x: hinge.x + baseLen, y: hinge.y)
            var basePath = Path()
            basePath.move(to: hinge)
            basePath.addLine(to: baseEnd)
            ctx.stroke(
                basePath,
                with: .color(baseColor),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            // Hinge dot
            let dot = Path(ellipseIn: CGRect(
                x: hinge.x - 4, y: hinge.y - 4, width: 8, height: 8
            ))
            ctx.fill(dot, with: .color(baseColor))

            // ── 2. Screen line (rotates around hinge) ─────────────────────────
            // angle=0 → overlaps base (closed); angle=90 → straight up; angle=180 → left
            let θ = angle * .pi / 180.0
            let screenEnd = CGPoint(
                x: hinge.x + cos(θ) * screenLen,
                y: hinge.y - sin(θ) * screenLen  // y-down: subtract to go up
            )
            var screenPath = Path()
            screenPath.move(to: hinge)
            screenPath.addLine(to: screenEnd)
            ctx.stroke(
                screenPath,
                with: .color(screenColor),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            // Screen tip cap
            let cap = Path(ellipseIn: CGRect(
                x: screenEnd.x - 3, y: screenEnd.y - 3, width: 6, height: 6
            ))
            ctx.fill(cap, with: .color(screenColor))

            // ── 3. Arc (goniometer) ───────────────────────────────────────────
            // Sweep from 0° (base/right) to -angle° (going upward = CCW visually).
            // In SwiftUI Canvas (y-down): clockwise:true = visual CCW (upward sweep).
            let color = angle > 180 ? overColor : arcColor
            var arcPath = Path()
            arcPath.addArc(
                center: hinge,
                radius: arcRadius,
                startAngle: .degrees(0),
                endAngle:   .degrees(-angle),
                clockwise:  true   // in y-down canvas: true = visual counter-clockwise (upward)
            )
            ctx.stroke(arcPath, with: .color(color.opacity(0.75)), style: StrokeStyle(
                lineWidth: 1.5, lineCap: .round, dash: [4, 3]
            ))

            // ── 4. "Closed" indicator ─────────────────────────────────────────
            if angle < 5 {
                ctx.draw(
                    Text("Closed")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.7)),
                    at: CGPoint(x: hinge.x + baseLen * 0.45, y: hinge.y - 18)
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MacBookProfileView(angle: 105)
        .frame(width: 360, height: 220)
        .padding()
        .background(FluxaTheme.surface)
}
