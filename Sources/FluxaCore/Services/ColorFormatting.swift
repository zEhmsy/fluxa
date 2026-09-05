import Foundation

// MARK: - ColorFormatting

package enum ColorFormatting {
    /// Formats sRGB components as uppercase `#RRGGBB`, clamping each channel to its valid range.
    package static func hex(red: Double, green: Double, blue: Double) -> String {
        String(
            format: "#%02X%02X%02X",
            channelByte(red),
            channelByte(green),
            channelByte(blue)
        )
    }

    private static func channelByte(_ component: Double) -> Int {
        let numericComponent = component.isNaN ? 0 : component
        let clampedComponent = min(max(numericComponent, 0), 1)
        let roundedByte = Int((clampedComponent * 255).rounded())
        return min(max(roundedByte, 0), 255)
    }
}
