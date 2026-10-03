import Foundation
import Testing
@testable import FluxaCore

@Suite("ScreenDrawTests")
struct ScreenDrawTests {

    @Test("ScreenDrawTool properties and shape drawing classification")
    func toolProperties() {
        #expect(ScreenDrawTool.pen.isDrawingShape == true)
        #expect(ScreenDrawTool.arrow.isDrawingShape == true)
        #expect(ScreenDrawTool.line.isDrawingShape == true)
        #expect(ScreenDrawTool.rectangle.isDrawingShape == true)
        #expect(ScreenDrawTool.ellipse.isDrawingShape == true)
        #expect(ScreenDrawTool.text.isDrawingShape == true)
        #expect(ScreenDrawTool.highlighter.isDrawingShape == true)

        #expect(ScreenDrawTool.laserPointer.isDrawingShape == false)
        #expect(ScreenDrawTool.spotlight.isDrawingShape == false)
        #expect(ScreenDrawTool.eraser.isDrawingShape == false)

        #expect(ScreenDrawTool.allCases.count == 10)
    }

    @Test("ScreenDrawColor presets and hex conversions")
    func colorPresetsAndHex() {
        #expect(ScreenDrawColor.red.hex == "#FF3B30")
        #expect(ScreenDrawColor.white.hex == "#FFFFFF")

        let clamped = ScreenDrawColor(red: -1.0, green: 2.0, blue: 0.5, alpha: -0.5)
        #expect(clamped.red == 0.0)
        #expect(clamped.green == 1.0)
        #expect(clamped.blue == 0.5)
        #expect(clamped.alpha == 0.0)
    }

    @Test("DrawingStroke hit-testing contains points near segments")
    func strokeHitTesting() {
        let p1 = DrawingPoint(x: 10, y: 10)
        let p2 = DrawingPoint(x: 100, y: 10)
        let stroke = DrawingStroke(
            tool: .pen,
            points: [p1, p2],
            color: .red,
            lineWidth: 6.0
        )

        // Point directly on segment
        #expect(stroke.contains(point: DrawingPoint(x: 50, y: 10), threshold: 4.0) == true)
        // Point slightly off segment within threshold (threshold 4 + lineWidth/2 3 = 7)
        #expect(stroke.contains(point: DrawingPoint(x: 50, y: 16), threshold: 4.0) == true)
        // Point far off segment
        #expect(stroke.contains(point: DrawingPoint(x: 50, y: 30), threshold: 4.0) == false)
    }

    @Test("DrawingStroke expiration and fade alpha computation")
    func strokeExpirationAndFade() {
        let baseDate = Date()
        let stroke = DrawingStroke(
            tool: .pen,
            points: [DrawingPoint(x: 0, y: 0)],
            color: .red,
            opacity: 1.0,
            createdAt: baseDate
        )

        let timeout: TimeInterval = 5.0

        // At t=0, not expired and full opacity
        #expect(stroke.isExpired(at: baseDate, timeout: timeout) == false)
        #expect(stroke.fadeAlpha(at: baseDate, timeout: timeout) == 1.0)

        // At t=4.5 (fade window is last 1.0s, so half faded)
        let halfwayDate = baseDate.addingTimeInterval(4.5)
        let halfwayAlpha = stroke.fadeAlpha(at: halfwayDate, timeout: timeout, fadeWindow: 1.0)
        #expect(halfwayAlpha > 0.4 && halfwayAlpha < 0.6)

        // At t=5.0, expired and zero opacity
        let expiredDate = baseDate.addingTimeInterval(5.0)
        #expect(stroke.isExpired(at: expiredDate, timeout: timeout) == true)
        #expect(stroke.fadeAlpha(at: expiredDate, timeout: timeout) == 0.0)
    }

    @Test("ArrowGeometry produces valid arrowhead wings for horizontal and vertical vectors")
    func arrowGeometryCalculations() {
        // Zero length or micro length returns nil
        let tooShort = ArrowGeometry.compute(
            start: DrawingPoint(x: 0, y: 0),
            end: DrawingPoint(x: 1, y: 1),
            lineWidth: 4.0
        )
        #expect(tooShort == nil)

        // Horizontal arrow from (0, 0) to (100, 0)
        let horiz = ArrowGeometry.compute(
            start: DrawingPoint(x: 0, y: 0),
            end: DrawingPoint(x: 100, y: 0),
            lineWidth: 4.0
        )
        #expect(horiz != nil)
        guard let horiz else { return }

        #expect(horiz.headTip.x == 100)
        #expect(horiz.headTip.y == 0)
        // For horizontal right-pointing arrow, left & right wings should be behind tip (x < 100)
        #expect(horiz.headLeft.x < 100)
        #expect(horiz.headRight.x < 100)
        // And symmetrically distributed along Y
        #expect(horiz.headLeft.y == -horiz.headRight.y)
    }

    @Test("StrokeSmoothing generates smooth midpoints for 3 or more points")
    func strokeSmoothingCalculations() {
        // Less than 3 points produces no quad curves
        #expect(StrokeSmoothing.smooth(points: []).isEmpty)
        #expect(StrokeSmoothing.smooth(points: [DrawingPoint(x: 0, y: 0)]).isEmpty)
        #expect(StrokeSmoothing.smooth(points: [DrawingPoint(x: 0, y: 0), DrawingPoint(x: 10, y: 10)]).isEmpty)

        // 4 points
        let p = [
            DrawingPoint(x: 0, y: 0),
            DrawingPoint(x: 10, y: 20),
            DrawingPoint(x: 20, y: 10),
            DrawingPoint(x: 30, y: 30)
        ]
        let segments = StrokeSmoothing.smooth(points: p)
        #expect(!segments.isEmpty)
        #expect(segments.first?.start == p[0])
        #expect(segments.last?.end == p[3])
    }

    @Test("DrawingHistory manages undo, redo, clear, eraser, and timeout pruning")
    func drawingHistoryLifecycle() {
        let history = DrawingHistory()
        #expect(history.canUndo == false)
        #expect(history.canRedo == false)

        let s1 = DrawingStroke(tool: .pen, points: [DrawingPoint(x: 10, y: 10), DrawingPoint(x: 20, y: 20)], color: .red)
        let s2 = DrawingStroke(tool: .arrow, points: [DrawingPoint(x: 50, y: 50), DrawingPoint(x: 80, y: 80)], color: .cyan)

        history.addStroke(s1)
        history.addStroke(s2)
        #expect(history.strokes.count == 2)
        #expect(history.canUndo == true)
        #expect(history.canRedo == false)

        // Undo
        let undone = history.undo()
        #expect(undone?.id == s2.id)
        #expect(history.strokes.count == 1)
        #expect(history.canRedo == true)

        // Redo
        let redone = history.redo()
        #expect(redone?.id == s2.id)
        #expect(history.strokes.count == 2)

        // Eraser hit-test on s1
        let erased = history.erase(at: DrawingPoint(x: 15, y: 15), radius: 5.0)
        #expect(erased.count == 1)
        #expect(erased.first?.id == s1.id)
        #expect(history.strokes.count == 1)
        #expect(history.strokes.first?.id == s2.id)

        // Clear is undoable
        _ = history.clear()
        #expect(history.strokes.isEmpty)
        #expect(history.canUndo == true)

        // Undo restored cleared strokes
        history.undo()
        #expect(history.strokes.count == 1)
        #expect(history.strokes.first?.id == s2.id)

        // Redo re-clears
        history.redo()
        #expect(history.strokes.isEmpty)

        // Pruning expired
        let oldDate = Date().addingTimeInterval(-10)
        let oldStroke = DrawingStroke(tool: .pen, points: [DrawingPoint(x: 0, y: 0)], color: .white, createdAt: oldDate)
        let newStroke = DrawingStroke(tool: .pen, points: [DrawingPoint(x: 5, y: 5)], color: .white, createdAt: Date())
        history.addStroke(oldStroke)
        history.addStroke(newStroke)

        let pruned = history.pruneExpired(timeout: 5.0)
        #expect(pruned.count == 1)
        #expect(pruned.first == oldStroke.id)
        #expect(history.strokes.count == 1)
        #expect(history.strokes.first?.id == newStroke.id)
    }

    @Test("ShapeConstraints snaps lines and arrows to 45 degree multiples")
    func shapeConstraintsAngleSnap() {
        let start = DrawingPoint(x: 100, y: 100)
        // Vector pointing at roughly ~10 degrees (dx=100, dy=20) -> should snap to 0 degrees (dy=0)
        let nearHorizontal = DrawingPoint(x: 200, y: 120)
        let snapped0 = ShapeConstraints.snap(start: start, current: nearHorizontal, tool: .line)
        #expect(abs(snapped0.y - start.y) < 0.001)
        #expect(snapped0.x > start.x)

        // Vector pointing at roughly ~40 degrees -> should snap to 45 degrees (dx == dy)
        let near45 = DrawingPoint(x: 200, y: 190)
        let snapped45 = ShapeConstraints.snap(start: start, current: near45, tool: .arrow)
        let dx = snapped45.x - start.x
        let dy = snapped45.y - start.y
        #expect(abs(dx - dy) < 0.001)
    }

    @Test("ShapeConstraints snaps rectangles and ellipses to square aspect ratio")
    func shapeConstraintsSquareSnap() {
        let start = DrawingPoint(x: 50, y: 50)
        let current = DrawingPoint(x: 120, y: 80) // dx=70, dy=30 -> side should be 70
        let snappedRect = ShapeConstraints.snap(start: start, current: current, tool: .rectangle)
        #expect(snappedRect.x == 120)
        #expect(snappedRect.y == 120)

        let snappedEllipse = ShapeConstraints.snap(start: start, current: current, tool: .ellipse)
        #expect(snappedEllipse.x == 120)
        #expect(snappedEllipse.y == 120)
    }

    @Test("DrawingStroke supports text annotations")
    func textStrokeCreation() {
        let origin = DrawingPoint(x: 150, y: 200)
        let stroke = DrawingStroke(
            tool: .text,
            points: [origin],
            color: .yellow,
            lineWidth: 18.0,
            text: "Important note"
        )
        #expect(stroke.tool == .text)
        #expect(stroke.text == "Important note")
        #expect(stroke.points.count == 1)
    }

    @Test("TextWrapping wraps long single line into multiple lines at word boundaries")
    func textWrappingLongLine() {
        let input = "This is a very long annotation note that definitely needs to wrap to several lines cleanly"
        let wrapped = TextWrapping.wrap(text: input, maxCharactersPerLine: 25)
        let lines = wrapped.components(separatedBy: "\n")
        #expect(lines.count > 1)
        for line in lines {
            #expect(line.count <= 25)
        }
        // Preserves all words
        #expect(wrapped.replacingOccurrences(of: "\n", with: " ") == input)
    }

    @Test("TextWrapping preserves explicit newlines")
    func textWrappingPreservesExplicitNewlines() {
        let input = "Line one\nLine two is longer and should wrap\nLine three"
        let wrapped = TextWrapping.wrap(text: input, maxCharactersPerLine: 20)
        let lines = wrapped.components(separatedBy: "\n")
        #expect(lines.count >= 3)
        #expect(lines[0] == "Line one")
        #expect(lines.last == "Line three")
    }

    @Test("DrawingStroke text eraser hit-tests across full bounding box")
    func textEraserBoundingBoxHitTest() {
        let origin = DrawingPoint(x: 100, y: 100)
        let stroke = DrawingStroke(
            tool: .text,
            points: [origin],
            color: .yellow,
            lineWidth: 16.0,
            text: "Hello World",
            textBoundsWidth: 120.0,
            textBoundsHeight: 30.0
        )

        // Point far away does not hit
        #expect(stroke.contains(point: DrawingPoint(x: 300, y: 300), threshold: 5.0) == false)

        // Point in middle of the word (e.g. x: 150, y: 115) hits!
        #expect(stroke.contains(point: DrawingPoint(x: 150, y: 115), threshold: 5.0) == true)

        // Point near right edge of the text box (x: 215, y: 115) hits!
        #expect(stroke.contains(point: DrawingPoint(x: 215, y: 115), threshold: 5.0) == true)
    }
}


