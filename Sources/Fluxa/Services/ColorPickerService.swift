import AppKit
import FluxaCore

// MARK: - ColorPickerService

@MainActor
final class ColorPickerService {
    private let sampler = NSColorSampler()
    private let feedbackPresenter = ColorPickerFeedbackPresenter()

    /// Runs the system sampler and copies an sRGB hex value. Cancellation leaves the clipboard
    /// untouched and returns false, as does a color that cannot be converted to sRGB.
    func pickColor() async -> Bool {
        await withCheckedContinuation { continuation in
            sampler.show { [weak self] sampledColor in
                // AppKit documents this callback as main-thread but does not annotate it
                // `@MainActor` in Swift, so bridge that guarantee explicitly.
                let didCopy = MainActor.assumeIsolated {
                    self?.copyAndShowFeedback(for: sampledColor) ?? false
                }
                continuation.resume(returning: didCopy)
            }
        }
    }

    private func copyAndShowFeedback(for sampledColor: NSColor?) -> Bool {
        guard let sampledColor,
              let color = sampledColor.usingColorSpace(.sRGB) else {
            return false
        }

        let hex = ColorFormatting.hex(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didCopy = pasteboard.setString(hex, forType: .string)
        if didCopy {
            feedbackPresenter.show(color: color, hex: hex)
        }
        return didCopy
    }
}
