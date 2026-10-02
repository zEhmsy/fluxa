import Foundation

/// The horizontal gap the notch occupies in the menu bar, in screen coordinates.
public struct NotchGeometry: Equatable, Sendable {
    /// Right edge of the usable area left of the notch.
    public var gapMinX: Double
    /// Left edge of the usable area right of the notch.
    public var gapMaxX: Double

    public init(gapMinX: Double, gapMaxX: Double) {
        self.gapMinX = gapMinX
        self.gapMaxX = gapMaxX
    }
}

/// Decides whether the menu bar strip should collapse to the logo because the notch hides it.
/// Collapsing is eager, expanding needs spare room plus a dwell, so the item never oscillates.
public enum NotchCollapse {
    /// Spare points beside the notch required before the full strip is shown again.
    public static let expandMargin: Double = 20
    /// Minimum time between two state changes.
    public static let minDwell: TimeInterval = 30

    /// The status item's horizontal extent in screen coordinates.
    public struct Frame: Equatable, Sendable {
        public var minX: Double
        public var maxX: Double

        public init(minX: Double, maxX: Double) {
            self.minX = minX
            self.maxX = maxX
        }
    }

    /// True when any part of the item sits at or left of the notch gap's right edge.
    public static func isObscured(item: Frame, notch: NotchGeometry?) -> Bool {
        guard let notch else { return false }
        return item.minX < notch.gapMaxX
    }

    /// True when a right-anchored item of `fullWidth` fits right of the notch with spare margin.
    public static func hasRoom(itemMaxX: Double, fullWidth: Double, notch: NotchGeometry?) -> Bool {
        guard let notch else { return true }
        return itemMaxX - notch.gapMaxX >= fullWidth + expandMargin
    }

    /// Returns the new `collapsed` value.
    public static func nextState(
        collapsed: Bool,
        item: Frame?,
        fullWidth: Double,
        notch: NotchGeometry?,
        lastChange: Date?,
        now: Date
    ) -> Bool {
        guard let notch else { return false }
        guard let item else { return collapsed }
        if let lastChange, now.timeIntervalSince(lastChange) < minDwell { return collapsed }

        if collapsed {
            return !hasRoom(itemMaxX: item.maxX, fullWidth: fullWidth, notch: notch)
        }
        return isObscured(item: item, notch: notch)
    }
}
