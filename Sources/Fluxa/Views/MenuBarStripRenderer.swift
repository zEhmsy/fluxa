import AppKit

// MARK: - MenuBarStripRenderer

/// Draws the menu bar item: the Fluxa switch mark, followed by one compact segment per agent the
/// user pinned ("CL 48%").
///
/// Rendered as a single template `NSImage` rather than a SwiftUI `HStack` label: the status item
/// sizes itself to whatever image it's handed, so composing the strip here gives exact control over
/// spacing and baseline, and one template image means macOS tints the whole thing for the light or
/// dark menu bar (and for the highlighted state) without any per-appearance work.
///
/// Because it's a template, the strip is monochrome — the severity colors live in the popover's
/// usage strip, where color is free.
enum MenuBarStripRenderer {

    /// One agent's reading in the menu bar.
    struct Segment: Equatable {
        /// Agent whose mark leads the segment.
        let providerID: String
        /// Window initial ("S", "W") — only set when one agent contributes more than one window,
        /// where two identical marks would otherwise be indistinguishable.
        let windowInitial: String?
        let percent: Int
    }

    /// Standard menu bar icon box.
    static let height: CGFloat = 18

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    /// Gap between the mark and the first reading.
    private static let markGap: CGFloat = 5
    /// Gap between two readings.
    private static let segmentGap: CGFloat = 7
    /// Agent mark size — a touch smaller than the Fluxa mark so the readings stay the loudest thing.
    private static let agentMarkSize: CGFloat = 11
    /// Gap between an agent's mark and its percentage.
    private static let agentMarkGap: CGFloat = 3

    // Geometry of `new-icon.svg`: a 24×24 viewBox whose ink only occupies a 20×14 rect inset by
    // (2, 5). Drawing the PDF into a plain 18×18 box would therefore render a 10.5pt mark — visibly
    // smaller than neighbouring menu bar icons. These constants scale the box so the *ink* lands at
    // `markInkHeight` and shift it so the ink starts at x = 0.
    private static let viewBoxSize: CGFloat = 24
    private static let artSize = CGSize(width: 20, height: 14)
    private static let artOrigin = CGPoint(x: 2, y: 5)
    /// Ink height that matches the optical weight of the system menu bar glyphs.
    private static let markInkHeight: CGFloat = 12

    private static var markScale: CGFloat { markInkHeight / artSize.height }
    private static var markBoxSize: CGFloat { viewBoxSize * markScale }
    private static var markInkWidth: CGFloat { artSize.width * markScale }

    // MARK: - Image

    static func image(segments: [Segment]) -> NSImage? {
        guard let mark = markImage() else { return nil }
        guard !segments.isEmpty else { return mark }

        let drawn = segments.map { segment in
            (mark: AgentMarks.image(for: segment.providerID, size: agentMarkSize),
             text: attributedText(for: segment))
        }
        let segmentWidths = drawn.map { entry in
            (entry.mark == nil ? 0 : agentMarkSize + agentMarkGap) + entry.text.size().width
        }
        let width = markInkWidth + markGap + segmentWidths.reduce(0, +) +
            segmentGap * CGFloat(max(0, drawn.count - 1))

        let strip = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            mark.draw(in: markRect)

            var x = markInkWidth + markGap
            for (index, entry) in drawn.enumerated() {
                if let agentMark = entry.mark {
                    agentMark.draw(in: NSRect(
                        x: x,
                        y: (height - agentMarkSize) / 2,
                        width: agentMarkSize,
                        height: agentMarkSize
                    ))
                    x += agentMarkSize + agentMarkGap
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

    private static func attributedText(for segment: Segment) -> NSAttributedString {
        let prefix = segment.windowInitial.map { "\($0) " } ?? ""
        return NSAttributedString(
            string: "\(prefix)\(segment.percent)%",
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

    /// Where to draw the mark's 24×24 box so its ink starts at x = 0 and is vertically centered.
    /// The box overhangs the strip on both axes; only the padding overhangs, never the ink.
    private static var markRect: NSRect {
        NSRect(
            x: -artOrigin.x * markScale,
            y: (height - markBoxSize) / 2,
            width: markBoxSize,
            height: markBoxSize
        )
    }

    // MARK: - Segment building

    /// Builds the segments for the pinned metrics. The window initial is only added when one agent
    /// contributes more than one window, so the common single-window case stays "mark + percentage".
    static func segments(for metrics: [AgentUsageMetric]) -> [Segment] {
        metrics.map { metric in
            let sameProvider = metrics.filter { $0.providerID == metric.providerID }
            let initial = sameProvider.count > 1
                ? metric.label.first.map { String($0).uppercased() }
                : nil
            return Segment(
                providerID: metric.providerID,
                windowInitial: initial,
                percent: metric.percentUsed
            )
        }
    }
}
