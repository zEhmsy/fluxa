import AppKit
import SwiftUI

// MARK: - SleekScrollView

/// A ScrollView wrapper that completely suppresses the bulky native AppKit scrollbar
/// (even when macOS has "Show scroll bars: Always" enabled) and provides an ultra-thin
/// (2.5px) custom indicator overlay that does not steal horizontal space from content.
struct SleekScrollView<Content: View>: View {
    var indicatorTint: Color = FluxaTheme.accent
    var indicatorPadding: EdgeInsets = EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 2)
    @ViewBuilder let content: () -> Content

    @StateObject private var coordinator = SleekScrollCoordinator()

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.vertical) {
                content()
                    .background(
                        SleekScrollBridge(coordinator: coordinator)
                    )
            }
            .scrollIndicators(.hidden)

            if coordinator.isScrollable {
                SleekScrollTrack(
                    coordinator: coordinator,
                    tint: indicatorTint
                )
                .padding(indicatorPadding)
            }
        }
    }
}

// MARK: - Coordinator

@MainActor
final class SleekScrollCoordinator: NSObject, ObservableObject {
    @Published var scrollProgress: CGFloat = 0
    @Published var thumbHeightRatio: CGFloat = 0
    @Published var isScrollable: Bool = false

    weak var scrollView: NSScrollView?

    func attach(to scrollView: NSScrollView) {
        if self.scrollView === scrollView {
            updateMetrics()
            return
        }

        detach()
        self.scrollView = scrollView

        // Suppress native scrollers completely
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller = nil
        scrollView.horizontalScroller = nil
        scrollView.autohidesScrollers = true

        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        clipView.postsFrameChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollNotification),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollNotification),
            name: NSView.frameDidChangeNotification,
            object: clipView
        )

        if let documentView = scrollView.documentView {
            documentView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScrollNotification),
                name: NSView.frameDidChangeNotification,
                object: documentView
            )
        }

        updateMetrics()
        DispatchQueue.main.async { [weak self] in
            self?.updateMetrics()
        }
    }

    func detach() {
        NotificationCenter.default.removeObserver(self)
        scrollView = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleScrollNotification(_ notification: Notification) {
        updateMetrics()
    }

    func updateMetrics() {
        guard let scrollView, let documentView = scrollView.documentView else {
            if isScrollable { isScrollable = false }
            return
        }

        if !documentView.postsFrameChangedNotifications {
            documentView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScrollNotification),
                name: NSView.frameDidChangeNotification,
                object: documentView
            )
        }

        let viewportHeight = scrollView.contentView.bounds.height
        let documentHeight = documentView.bounds.height
        let maxScroll = documentHeight - viewportHeight

        if maxScroll > 1 && viewportHeight > 0 {
            let currentY = scrollView.contentView.bounds.origin.y
            let progress = max(0, min(1, currentY / maxScroll))
            let ratio = max(0.08, min(1.0, viewportHeight / documentHeight))

            if scrollProgress != progress || thumbHeightRatio != ratio || !isScrollable {
                scrollProgress = progress
                thumbHeightRatio = ratio
                isScrollable = true
            }
        } else if isScrollable {
            isScrollable = false
        }
    }

    func scrollTo(fraction: CGFloat) {
        guard let scrollView, let documentView = scrollView.documentView else { return }
        let maxScroll = documentView.bounds.height - scrollView.contentView.bounds.height
        guard maxScroll > 0 else { return }
        let targetY = max(0, min(maxScroll, fraction * maxScroll))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

// MARK: - AppKit Bridge

private struct SleekScrollBridge: NSViewRepresentable {
    let coordinator: SleekScrollCoordinator

    func makeNSView(context: Context) -> BridgeNSView {
        BridgeNSView(coordinator: coordinator)
    }

    func updateNSView(_ nsView: BridgeNSView, context: Context) {
        nsView.coordinator = coordinator
        nsView.checkAttachment()
    }

    final class BridgeNSView: NSView {
        var coordinator: SleekScrollCoordinator

        init(coordinator: SleekScrollCoordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            checkAttachment()
        }

        func checkAttachment() {
            guard let scrollView = enclosingScrollView else { return }
            coordinator.attach(to: scrollView)
        }
    }
}

// MARK: - Track & Indicator

private struct SleekScrollTrack: View {
    @ObservedObject var coordinator: SleekScrollCoordinator
    var tint: Color

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let trackHeight = geometry.size.height
            let thumbHeight = max(24, trackHeight * coordinator.thumbHeightRatio)
            let availableTravel = max(0, trackHeight - thumbHeight)
            let thumbY = availableTravel * coordinator.scrollProgress

            ZStack(alignment: .topTrailing) {
                // Invisible hit-target for comfortable grabbing/hovering
                Color.clear
                    .frame(width: 10)
                    .contentShape(Rectangle())

                // The ultra-thin capsule indicator
                Capsule()
                    .fill(thumbColor)
                    .frame(width: isHovering || isDragging ? 3.5 : 2.5, height: thumbHeight)
                    .offset(y: thumbY)
                    .animation(.easeOut(duration: 0.12), value: isHovering || isDragging)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        let progress = max(0, min(1, (value.location.y - thumbHeight / 2) / max(1, availableTravel)))
                        coordinator.scrollTo(fraction: progress)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(width: 10)
        .allowsHitTesting(true)
    }

    private var thumbColor: Color {
        if isDragging {
            return tint.opacity(0.85)
        } else if isHovering {
            return tint.opacity(0.65)
        } else {
            return Color.secondary.opacity(0.38)
        }
    }
}
