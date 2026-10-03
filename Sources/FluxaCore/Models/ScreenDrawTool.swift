import Foundation

// MARK: - ScreenDrawTool

/// Tool types available for on-screen drawing and presentations.
package enum ScreenDrawTool: String, CaseIterable, Identifiable, Codable, Sendable {
    case pen
    case arrow
    case line
    case rectangle
    case ellipse
    case text
    case highlighter
    case laserPointer
    case spotlight
    case eraser

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .highlighter: return "Highlighter"
        case .laserPointer: return "Laser"
        case .spotlight: return "Spotlight"
        case .eraser: return "Eraser"
        }
    }

    package var sfSymbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "character.cursor.ibeam"
        case .highlighter: return "highlighter"
        case .laserPointer: return "scope"
        case .spotlight: return "flashlight.on.fill"
        case .eraser: return "eraser.fill"
        }
    }

    /// Whether this tool creates a permanent/drawn stroke in the history.
    package var isDrawingShape: Bool {
        switch self {
        case .pen, .arrow, .line, .rectangle, .ellipse, .text, .highlighter:
            return true
        case .laserPointer, .spotlight, .eraser:
            return false
        }
    }
}

// MARK: - ScreenDrawMode

/// Operating mode for on-screen drawing.
package enum ScreenDrawMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard
    case disappearing
    case laser
    case spotlight

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .disappearing: return "Fade-out"
        case .laser: return "Laser"
        case .spotlight: return "Spotlight"
        }
    }
}

// MARK: - ScreenDrawBackground

/// Background canvas style during drawing mode.
package enum ScreenDrawBackground: String, CaseIterable, Identifiable, Codable, Sendable {
    case transparent
    case blackboard
    case whiteboard

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .transparent: return "Desktop"
        case .blackboard: return "Blackboard"
        case .whiteboard: return "Whiteboard"
        }
    }
}

// MARK: - ScreenDrawColor

/// RGBA representation of a drawing color, decoupled from AppKit/SwiftUI.
package struct ScreenDrawColor: Codable, Equatable, Sendable, Hashable {
    package var red: Double
    package var green: Double
    package var blue: Double
    package var alpha: Double

    package init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    package var hex: String {
        ColorFormatting.hex(red: red, green: green, blue: blue)
    }

    package static let red = ScreenDrawColor(red: 1.0, green: 0.23, blue: 0.19)
    package static let orange = ScreenDrawColor(red: 1.0, green: 0.58, blue: 0.0)
    package static let yellow = ScreenDrawColor(red: 1.0, green: 0.80, blue: 0.0)
    package static let green = ScreenDrawColor(red: 0.20, green: 0.78, blue: 0.35)
    package static let cyan = ScreenDrawColor(red: 0.20, green: 0.68, blue: 0.90)
    package static let purple = ScreenDrawColor(red: 0.69, green: 0.32, blue: 0.87)
    package static let white = ScreenDrawColor(red: 1.0, green: 1.0, blue: 1.0)

    package static let presetPalette: [ScreenDrawColor] = [
        .red, .orange, .yellow, .green, .cyan, .purple, .white
    ]
}
