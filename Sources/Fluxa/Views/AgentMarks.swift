import AppKit
import SwiftUI

// MARK: - AgentMarks

/// The agents' own marks, drawn from vector PDFs generated out of the vendors' SVG logos
/// (`Resources/AgentIcons`, regenerate with
/// `rsvg-convert -f pdf -o <name>.pdf <name>.svg`).
///
/// Always rendered monochrome — as template images in the menu bar, as a single-color shape in the
/// popover. Beyond matching the menu bar's tinting, it keeps several vendor logos side by side from
/// turning a 300pt row into a color clash, and it's what the marks are there for: identifying which
/// agent a number belongs to, not reproducing brand color.
enum AgentMarks {

    /// Marks are square with the artwork filling the box, so the drawn size is the ink size.
    static func image(for providerID: String, size: CGFloat) -> NSImage? {
        guard let url = Bundle.fluxaResources.url(
            forResource: providerID,
            withExtension: "pdf",
            subdirectory: "AgentIcons"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }

    /// SF Symbol shown when an agent ships no mark — a new provider added before its logo is.
    static let fallbackSymbol = "gauge.with.dots.needle.33percent"
}

// MARK: - AgentMarkView

/// SwiftUI wrapper for a mark, tinted with the current foreground style.
struct AgentMarkView: View {
    let providerID: String
    var size: CGFloat = 11

    var body: some View {
        if let image = AgentMarks.image(for: providerID, size: size) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: AgentMarks.fallbackSymbol)
                .font(.system(size: size * 0.9))
        }
    }
}
