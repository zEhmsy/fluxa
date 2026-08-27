import SwiftUI

// MARK: - FluxCutShape

/// Rectangular module with the Control Deck's diagonal bottom-right energy cut.
struct FluxCutShape: InsettableShape {
    var cut: CGFloat = 8
    private var insetAmount: CGFloat = 0

    init(cut: CGFloat = 8) {
        self.cut = cut
    }

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let resolvedCut = min(cut, bounds.width * 0.32, bounds.height * 0.42)

        var path = Path()
        path.move(to: CGPoint(x: bounds.minX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - resolvedCut))
        path.addLine(to: CGPoint(x: bounds.maxX - resolvedCut, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> FluxCutShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

// MARK: - Rail

enum ControlDeckRailNode {
    case none
    case hollow(Color)
    case filled(Color)
    case terminal
}

/// One vertically composable cell of the Flux rail. Every section owns its own cell, avoiding a
/// global geometry overlay that would become fragile when metrics or actions are hidden.
struct ControlDeckRailCell: View {
    let palette: ControlDeckPalette
    var node: ControlDeckRailNode = .none
    var segmentColor: Color?
    var showsBranch = false
    var isPulsing = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(palette.border)
                .frame(width: 1.5)

            if let segmentColor {
                Rectangle()
                    .fill(segmentColor)
                    .frame(width: 2)
                    .opacity(isPulsing ? 1 : 0.82)
                    .scaleEffect(x: 1, y: isPulsing ? 1 : 0.88)
                    .animation(.easeOut(duration: 0.22), value: isPulsing)
            }

            if showsBranch {
                HStack(spacing: 0) {
                    Spacer(minLength: 20)
                    Rectangle()
                        .fill(segmentColor ?? palette.border)
                        .frame(width: 20, height: segmentColor == nil ? 1.5 : 2)
                }
            }

            nodeView
        }
        .frame(width: 40)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var nodeView: some View {
        switch node {
        case .none:
            EmptyView()
        case .hollow(let color):
            Rectangle()
                .fill(palette.deck)
                .frame(width: 9, height: 9)
                .overlay { Rectangle().stroke(color, lineWidth: 1.5) }
                .rotationEffect(.degrees(45))
        case .filled(let color):
            Rectangle()
                .fill(color)
                .frame(width: 9, height: 9)
                .rotationEffect(.degrees(45))
        case .terminal:
            Rectangle()
                .fill(palette.brandGradient)
                .frame(width: 13, height: 13)
                .rotationEffect(.degrees(45))
        }
    }
}

// MARK: - Section Header

struct ControlDeckSectionHeader: View {
    let title: String
    let trailing: String?
    let nodeColor: Color
    let palette: ControlDeckPalette
    var trailingColor: Color?

    var body: some View {
        HStack(spacing: 0) {
            ControlDeckRailCell(palette: palette, node: .hollow(nodeColor))

            HStack {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(palette.secondaryText)

                Spacer()

                if let trailing {
                    Text(trailing.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(trailingColor ?? palette.tertiaryText)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
        }
        .frame(height: 22)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Buttons and status

struct ControlDeckCutButtonStyle: ButtonStyle {
    let tint: Color
    let palette: ControlDeckPalette
    var reduceMotion = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                configuration.isPressed ? palette.pressed : tint.opacity(palette.isDark ? 0.12 : 0.08),
                in: FluxCutShape(cut: 6)
            )
            .overlay { FluxCutShape(cut: 6).stroke(tint.opacity(0.34), lineWidth: 1) }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ControlDeckStatusPill: View {
    enum Marker: Equatable {
        case warning
        case critical
    }

    let text: String
    let tint: Color
    var marker: Marker?

    var body: some View {
        HStack(spacing: 4) {
            if marker == .warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 7, weight: .bold))
            } else if marker == .critical {
                Rectangle().frame(width: 6, height: 6)
            }

            Text(text.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.35)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .overlay { RoundedRectangle(cornerRadius: 3).stroke(tint.opacity(0.55), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}
