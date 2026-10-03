import FluxaCore
import SwiftUI

// MARK: - ScreenDrawCanvasView

/// Canvas rendering completed strokes, live in-progress drawing, laser pointer glow,
/// and spotlight hole masks across a display.
struct ScreenDrawCanvasView: View {

    @Bindable var service: ScreenDrawService
    let screenFrame: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                Canvas { context, size in
                    // 1. Blackboard / Whiteboard background
                    drawBackground(context: context, size: size)

                    // 2. Spotlight Mask (if spotlight tool active)
                    if service.activeTool == .spotlight, let spotPos = service.spotlightPosition {
                        drawSpotlight(context: context, size: size, at: spotPos, radius: service.spotlightRadius)
                    }

                    // 3. Completed strokes from history
                    let now = timeline.date
                    for stroke in service.history.strokes {
                        let alpha = (service.activeMode == .disappearing)
                            ? stroke.fadeAlpha(at: now, timeout: service.disappearingTimeout)
                            : stroke.opacity

                        guard alpha > 0.01 else { continue }
                        drawStroke(stroke, alpha: alpha, context: &context)
                    }

                    // 4. Live in-progress stroke preview
                    if !service.activePoints.isEmpty && service.activeTool.isDrawingShape && service.activeTool != .text {
                        drawActiveStroke(context: &context)
                    }

                    // 5. Laser Pointer (if laser tool active)
                    if service.activeTool == .laserPointer, let laserPos = service.laserPosition {
                        drawLaser(context: &context, at: laserPos)
                    }
                }
            }

            // 6. Active Text Input Session
            if let session = service.activeTextSession {
                ScreenDrawInlineTextInput(service: service, screenFrame: screenFrame)
                    .offset(x: session.position.x - 8, y: session.position.y - 5)
            }
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .ignoresSafeArea()
    }

    // MARK: - Background

    private func drawBackground(context: GraphicsContext, size: CGSize) {
        switch service.background {
        case .transparent:
            break
        case .blackboard:
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.10, opacity: 0.96)))
        case .whiteboard:
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.98, opacity: 0.96)))
        }
    }

    // MARK: - Spotlight

    private func drawSpotlight(context: GraphicsContext, size: CGSize, at center: CGPoint, radius: CGFloat) {
        var path = Path(CGRect(origin: .zero, size: size))
        let holeRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        path.addEllipse(in: holeRect)
        // Even-odd fill rule cuts the circle out of the fullscreen rectangle
        context.fill(path, with: .color(Color.black.opacity(0.68)), style: FillStyle(eoFill: true))

        var ringPath = Path()
        ringPath.addEllipse(in: holeRect)
        context.stroke(ringPath, with: .color(.white.opacity(0.4)), lineWidth: 2)
    }

    // MARK: - Laser Pointer

    private func drawLaser(context: inout GraphicsContext, at center: CGPoint) {
        let laserColor = Color(
            red: service.selectedColor.red,
            green: service.selectedColor.green,
            blue: service.selectedColor.blue
        )
        let uptime = ProcessInfo.processInfo.systemUptime

        // 1. Fading trail of recent cursor positions (~0.4s window)
        if service.laserTrail.count >= 2 {
            for i in 0..<(service.laserTrail.count - 1) {
                let s1 = service.laserTrail[i]
                let s2 = service.laserTrail[i + 1]
                let age = uptime - s1.timestamp
                guard age < 0.40 else { continue }
                let progress = 1.0 - (age / 0.40)
                let alpha = progress * 0.55
                let width = max(2.5, 12.0 * progress)

                var trailPath = Path()
                trailPath.move(to: s1.point)
                trailPath.addLine(to: s2.point)
                context.stroke(
                    trailPath,
                    with: .color(laserColor.opacity(alpha)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
            }
        }

        // 2. Glowing laser head
        let coreRadius: CGFloat = 6.0
        let haloRadius: CGFloat = 20.0

        // Outer neon glow
        let haloRect = CGRect(x: center.x - haloRadius, y: center.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)
        context.fill(
            Path(ellipseIn: haloRect),
            with: .color(laserColor.opacity(0.35))
        )

        // Mid glow
        let midRect = CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22)
        context.fill(
            Path(ellipseIn: midRect),
            with: .color(laserColor.opacity(0.70))
        )

        // Bright white core (ensures high contrast on any background)
        let coreRect = CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)
        context.fill(
            Path(ellipseIn: coreRect),
            with: .color(.white)
        )
    }

    // MARK: - Stroke Drawing

    private func drawStroke(_ stroke: DrawingStroke, alpha: Double, context: inout GraphicsContext) {
        let color = Color(
            red: stroke.color.red,
            green: stroke.color.green,
            blue: stroke.color.blue,
            opacity: alpha
        )

        switch stroke.tool {
        case .pen, .highlighter:
            let path = smoothedPath(from: stroke.points)
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
            )

        case .arrow:
            guard stroke.points.count >= 2 else { return }
            let p1 = stroke.points[0]
            let p2 = stroke.points[stroke.points.count - 1]
            guard let arrow = ArrowGeometry.compute(start: p1, end: p2, lineWidth: stroke.lineWidth) else { return }

            // Shaft
            var shaftPath = Path()
            shaftPath.move(to: CGPoint(x: arrow.shaftStart.x, y: arrow.shaftStart.y))
            shaftPath.addLine(to: CGPoint(x: arrow.shaftEnd.x, y: arrow.shaftEnd.y))
            context.stroke(shaftPath, with: .color(color), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round))

            // Head polygon
            var headPath = Path()
            let headPoints = arrow.headPolygon
            if !headPoints.isEmpty {
                headPath.move(to: CGPoint(x: headPoints[0].x, y: headPoints[0].y))
                for pt in headPoints.dropFirst() {
                    headPath.addLine(to: CGPoint(x: pt.x, y: pt.y))
                }
                headPath.closeSubpath()
                context.fill(headPath, with: .color(color))
            }

        case .line:
            guard stroke.points.count >= 2 else { return }
            let p1 = stroke.points[0]
            let p2 = stroke.points[stroke.points.count - 1]
            var path = Path()
            path.move(to: CGPoint(x: p1.x, y: p1.y))
            path.addLine(to: CGPoint(x: p2.x, y: p2.y))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round))

        case .rectangle:
            guard stroke.points.count >= 2 else { return }
            let rect = rectFromPoints(stroke.points[0], stroke.points[stroke.points.count - 1])
            let path = Path(roundedRect: rect, cornerRadius: 4)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: stroke.lineWidth, lineJoin: .round))

        case .ellipse:
            guard stroke.points.count >= 2 else { return }
            let rect = rectFromPoints(stroke.points[0], stroke.points[stroke.points.count - 1])
            let path = Path(ellipseIn: rect)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: stroke.lineWidth))

        case .text:
            guard let text = stroke.text, !text.isEmpty, let p1 = stroke.points.first else { return }
            let fontSize = max(16.0, stroke.lineWidth * 2.5)
            let resolved = context.resolve(
                Text(text)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            )
            context.draw(resolved, at: CGPoint(x: p1.x, y: p1.y), anchor: .topLeading)

        default:
            break
        }
    }

    private func drawActiveStroke(context: inout GraphicsContext) {
        let opacity = (service.activeTool == .highlighter) ? 0.45 : 1.0
        let effectiveWidth = (service.activeTool == .highlighter) ? service.strokeWidth * 2.5 : service.strokeWidth
        let dummyStroke = DrawingStroke(
            tool: service.activeTool,
            points: service.activePoints,
            color: service.selectedColor,
            lineWidth: effectiveWidth,
            opacity: opacity
        )
        drawStroke(dummyStroke, alpha: opacity, context: &context)
    }

    // MARK: - Geometry Helpers

    private func smoothedPath(from points: [DrawingPoint]) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }
        path.move(to: CGPoint(x: points[0].x, y: points[0].y))

        if points.count < 3 {
            for pt in points.dropFirst() {
                path.addLine(to: CGPoint(x: pt.x, y: pt.y))
            }
            return path
        }

        let segments = StrokeSmoothing.smooth(points: points)
        for seg in segments {
            path.addQuadCurve(
                to: CGPoint(x: seg.end.x, y: seg.end.y),
                control: CGPoint(x: seg.control.x, y: seg.control.y)
            )
        }
        return path
    }

    private func rectFromPoints(_ p1: DrawingPoint, _ p2: DrawingPoint) -> CGRect {
        let minX = min(p1.x, p2.x)
        let maxX = max(p1.x, p2.x)
        let minY = min(p1.y, p2.y)
        let maxY = max(p1.y, p2.y)
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }
}

// MARK: - ScreenDrawInlineTextInput

/// Floating lightweight text input widget allowing presenters to click anywhere and type annotations.
/// Dynamically expands horizontally to fit typed text, wrapping into multiple lines when reaching max width.
struct ScreenDrawInlineTextInput: View {
    @Bindable var service: ScreenDrawService
    let screenFrame: CGRect
    @FocusState private var isFocused: Bool

    private var fontSize: Double {
        max(16.0, service.strokeWidth * 2.5)
    }

    private var currentText: String {
        service.activeTextSession?.text ?? ""
    }

    private var maxAllowedWidth: CGFloat {
        guard let session = service.activeTextSession else { return 450 }
        let remaining = screenFrame.width - session.position.x - 30
        return max(180, min(480, remaining))
    }

    var body: some View {
        if service.activeTextSession != nil {
            let textColor = Color(
                red: service.selectedColor.red,
                green: service.selectedColor.green,
                blue: service.selectedColor.blue
            )

            ZStack(alignment: .topLeading) {
                // Invisible measuring text that dictates ideal width/height
                Text(currentText.isEmpty ? "Testo..." : currentText)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .lineLimit(nil)
                    .opacity(0)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: maxAllowedWidth, alignment: .leading)

                // Multiline-capable plain text field
                TextField("Testo...", text: Binding(
                    get: { service.activeTextSession?.text ?? "" },
                    set: { service.activeTextSession?.text = $0 }
                ), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)
                .lineLimit(1...10)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .focused($isFocused)
            }
            .frame(minWidth: 80, maxWidth: maxAllowedWidth, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.68))
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(textColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            )
            .onAppear {
                isFocused = true
            }
        }
    }
}

