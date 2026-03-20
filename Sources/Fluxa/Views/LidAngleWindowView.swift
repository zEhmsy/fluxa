import SwiftUI

// MARK: - LidAngleWindowView

/// Dedicated window that shows the MacBook lid angle as an animated side-profile diagram.
struct LidAngleWindowView: View {

    @Environment(PopoverViewModel.self) private var viewModel

    /// Smoothed angle used for animation — updated from the monitor via withAnimation.
    @State private var displayAngle: Double = 90

    private var monitor: LidAngleMonitor { viewModel.lidAngleMonitor }

    var body: some View {
        ZStack {
            // Dark background
            Color(red: 0.08, green: 0.08, blue: 0.10)
                .ignoresSafeArea()

            if monitor.isAvailable {
                VStack(spacing: 20) {
                    MacBookProfileView(angle: displayAngle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    statusLabel
                        .padding(.bottom, 16)
                }
            } else {
                unavailableView
            }
        }
        .frame(width: 340, height: 280)
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

    // MARK: - Subviews

    private var statusLabel: some View {
        Group {
            if displayAngle < 5 {
                Label("Closed", systemImage: "laptopcomputer.slash")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text("Lid Angle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Lid Angle Not Available")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            Text("This sensor is only present on MacBook models.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .colorScheme(.dark)
    }
}

// MARK: - MacBookProfileView

/// Custom Canvas that draws a side-profile MacBook silhouette:
/// - A fixed horizontal base line (top case / keyboard deck).
/// - A screen line that rotates from the hinge based on `angle`.
/// - A goniometer arc between the two lines with the degree value.
struct MacBookProfileView: View {

    /// Lid angle in degrees (0 = closed, 90 = upright, 180 = fully flat open).
    let angle: Double

    // Design constants
    private let baseColor   = Color(white: 0.65)
    private let screenColor = Color(white: 0.85)
    private let arcColor    = Color.blue
    private let overColor   = Color.orange   // used when angle > 180°

    var body: some View {
        Canvas { ctx, size in
            let hinge = CGPoint(x: size.width * 0.32, y: size.height * 0.68)
            let baseLen:   CGFloat = size.width  * 0.54
            let screenLen: CGFloat = size.height * 0.52
            let arcRadius: CGFloat = 52
            let lineWidth: CGFloat = 2.0

            // ── 1. Base line (top case, horizontal, going right) ──────────────
            let baseEnd = CGPoint(x: hinge.x + baseLen, y: hinge.y)
            var basePath = Path()
            basePath.move(to: hinge)
            basePath.addLine(to: baseEnd)
            ctx.stroke(basePath, with: .color(baseColor), lineWidth: lineWidth)

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
            ctx.stroke(screenPath, with: .color(screenColor), lineWidth: lineWidth)

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

            // ── 4. Degree label on the arc mid-point ─────────────────────────
            let midθ = (angle / 2.0) * .pi / 180.0
            let labelRadius: CGFloat = arcRadius + 22
            let labelCenter = CGPoint(
                x: hinge.x + cos(midθ) * labelRadius,
                y: hinge.y - sin(midθ) * labelRadius
            )

            let formatted = String(format: "%.1f°", angle)
            ctx.draw(
                Text(formatted)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(color.opacity(0.9)),
                at: labelCenter
            )

            // ── 5. "Closed" indicator ─────────────────────────────────────────
            if angle < 5 {
                ctx.draw(
                    Text("Chiuso")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.7)),
                    at: CGPoint(x: hinge.x + baseLen * 0.45, y: hinge.y - 18)
                )
            }
        }
        .colorScheme(.dark)
    }
}

// MARK: - Preview

#Preview {
    MacBookProfileView(angle: 105)
        .frame(width: 340, height: 240)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
}
