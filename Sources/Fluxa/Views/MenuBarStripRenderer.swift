import AppKit
import FluxaCore

// MARK: - MenuBarStripRenderer

/// Draws one compact segment per reading the user pinned — system stats first ("􀫥 42%"), then
/// agent quotas ("CL 48%"). The Fluxa mark is used only when no readings are selected, ensuring the
/// status item always remains visible and clickable without wasting space beside live metrics.
///
/// Rendered as a single template `NSImage` rather than a SwiftUI `HStack` label: the status item
/// sizes itself to whatever image it's handed, so composing the strip here gives exact control over
/// spacing and baseline, and one template image means macOS tints the whole thing for the light or
/// dark menu bar (and for the highlighted state) without any per-appearance work.
///
/// Because it's a template, the strip is monochrome — the severity colors live in the popover's
/// strips, where color is free.
enum MenuBarStripRenderer {

    /// One reading in the menu bar: something small that identifies it, followed by the value.
    struct Segment: Equatable {

        /// What identifies the reading at 11pt. Both cases draw into the same square box, so
        /// system and agent segments line up on the same baseline.
        enum Leading: Equatable {
            /// An agent's vendor mark, drawn from the bundled vector PDFs.
            case agentMark(providerID: String)
            /// An SF Symbol, for system readings.
            case symbol(name: String)
        }

        let leading: Leading
        /// The value as drawn: "48%", "58°". Agent segments may prefix a window initial ("S 48%")
        /// when one agent contributes more than one window.
        let text: String
    }

    /// Standard menu bar icon box.
    static let height: CGFloat = 18

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    /// Gap between two readings.
    private static let segmentGap: CGFloat = 7
    /// Leading-glyph size — a touch smaller than the Fluxa mark so the readings stay the loudest thing.
    private static let agentMarkSize: CGFloat = 11
    /// Gap between a segment's glyph and its value.
    private static let agentMarkGap: CGFloat = 3

    // Geometry of `new-icon.svg`: a 24×24 viewBox whose ink is only 14pt tall. Scaling the fallback
    // box from that ink height keeps the mark optically aligned with neighbouring menu bar icons.
    private static let viewBoxSize: CGFloat = 24
    private static let artSize = CGSize(width: 20, height: 14)
    /// Ink height that matches the optical weight of the system menu bar glyphs.
    private static let markInkHeight: CGFloat = 12

    private static var markScale: CGFloat { markInkHeight / artSize.height }
    private static var markBoxSize: CGFloat { viewBoxSize * markScale }

    // MARK: - Image

    static func image(segments: [Segment]) -> NSImage? {
        guard !segments.isEmpty else { return markImage() }

        let drawn = segments.map { segment in
            (mark: leadingImage(for: segment.leading),
             text: attributedText(for: segment))
        }
        // Glyph widths are measured rather than assumed square: the agent marks are, but SF Symbols
        // like `memorychip` are wider than tall, and forcing them into a square box would squash them.
        let glyphWidths = drawn.map { entry in entry.mark.map(glyphWidth) ?? 0 }
        let segmentWidths = zip(drawn, glyphWidths).map { entry, glyph in
            (glyph == 0 ? 0 : glyph + agentMarkGap) + entry.text.size().width
        }
        let width = segmentWidths.reduce(0, +) +
            segmentGap * CGFloat(max(0, drawn.count - 1))

        let strip = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (index, entry) in drawn.enumerated() {
                if let glyph = entry.mark {
                    let glyphSize = glyphWidths[index]
                    glyph.draw(in: NSRect(
                        x: x,
                        y: (height - agentMarkSize) / 2,
                        width: glyphSize,
                        height: agentMarkSize
                    ))
                    x += glyphSize + agentMarkGap
                }
                let size = entry.text.size()
                entry.text.draw(at: NSPoint(x: x, y: (height - size.height) / 2))
                x += size.width + (index == drawn.count - 1 ? 0 : segmentGap)
            }
            return true
        }
        strip.isTemplate = true
        return strip
    }

    /// The glyph that opens a segment. SF Symbols are configured at the mark's own point size and
    /// flagged as templates so they tint with the rest of the strip.
    private static func leadingImage(for leading: Segment.Leading) -> NSImage? {
        switch leading {
        case .agentMark(let providerID):
            return AgentMarks.image(for: providerID, size: agentMarkSize)

        case .symbol(let name):
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
                return nil
            }
            let configured = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: agentMarkSize, weight: .medium)
            ) ?? image
            configured.isTemplate = true
            return configured
        }
    }

    private static func attributedText(for segment: Segment) -> NSAttributedString {
        NSAttributedString(
            string: segment.text,
            attributes: [
                .font: font,
                // Black: a template image is tinted from its alpha channel, so the color only has
                // to be fully opaque.
                .foregroundColor: NSColor.black,
            ]
        )
    }

    /// The switch mark, loaded from the vector PDF generated out of `new-icon.svg`. PDF (not PNG)
    /// so the mark stays sharp at any scale factor.
    private static func markImage() -> NSImage? {
        guard let url = Bundle.fluxaResources.url(forResource: "menu-icon", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: markBoxSize, height: markBoxSize)
        image.isTemplate = true
        return image
    }

    /// Width the glyph occupies once scaled to the strip's glyph height, preserving its aspect.
    private static func glyphWidth(_ image: NSImage) -> CGFloat {
        let size = image.size
        guard size.height > 0 else { return agentMarkSize }
        return size.width * (agentMarkSize / size.height)
    }

    // MARK: - Segment building

    /// Builds the segments for the pinned agent metrics. The window initial is only added when one
    /// agent contributes more than one window, so the common single-window case stays
    /// "mark + percentage".
    static func segments(for metrics: [AgentUsageMetric]) -> [Segment] {
        metrics.map { metric in
            let sameProvider = metrics.filter { $0.providerID == metric.providerID }
            let prefix = sameProvider.count > 1
                ? metric.label.first.map { "\(String($0).uppercased()) " } ?? ""
                : ""
            return Segment(
                leading: .agentMark(providerID: metric.providerID),
                text: "\(prefix)\(metric.percentUsed)%"
            )
        }
    }

    /// Builds the segments for the pinned system readings.
    static func segments(for metrics: [SystemMetric]) -> [Segment] {
        metrics.map { metric in
            Segment(leading: .symbol(name: metric.id.symbolName), text: metric.displayText)
        }
    }

    /// Assembles the whole strip: system readings first, agent quotas after, truncated to the shared
    /// menu bar budget.
    ///
    /// System comes first because it is the faster-moving half — putting the numbers that change
    /// every couple of seconds first keeps them in one place instead of letting an agent percentage
    /// appearing or vanishing shift them around.
    static func combinedSegments(
        system: [SystemMetric],
        agents: [AgentUsageMetric],
        limit: Int
    ) -> [Segment] {
        Array((segments(for: system) + segments(for: agents)).prefix(limit))
    }
}
