import SwiftUI

// MARK: - AnimatedMeshGradientView

/// A sunrise mesh gradient in Fluxa's brand colours: violet over blue, with a cyan sun that
/// breathes at the bottom edge. Setting
/// `revealed` sweeps the colour up from the bottom; clearing it sets it back down. The nodes drift on
/// incommensurate periods so the loop never visibly repeats. Rendering is GPU-side (`MeshGradient` on
/// macOS 15, a flattened blur stack on 14), capped at 30 fps, and still under Reduce Motion.
struct AnimatedMeshGradientView: View {
    var revealed = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rise: CGFloat = 0
    @State private var start = Date()

    static let riseDuration = 0.9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
            surface(t: t)
        }
        .mask { riseMask }
        .onAppear {
            start = Date()
            setRise(revealed)
        }
        .onChange(of: revealed) { _, newValue in setRise(newValue) }
        .accessibilityHidden(true)
    }

    private func setRise(_ up: Bool) {
        guard !reduceMotion else { rise = up ? 1 : 0; return }
        withAnimation(up ? .timingCurve(0.22, 1, 0.36, 1, duration: Self.riseDuration)
                         : .timingCurve(0.64, 0, 0.78, 0, duration: Self.riseDuration * 0.7)) {
            rise = up ? 1 : 0
        }
    }

    @ViewBuilder
    private func surface(t: TimeInterval) -> some View {
        if #available(macOS 15.0, *) {
            MeshGradient(width: 3, height: 3, points: Self.points(t: t), colors: Self.colors(t: t))
        } else {
            fallback(t: t)
        }
    }

    // MARK: Palette

    /// The Control Deck brand pair, with the CPU cyan as the light source.
    private static let violet = ControlDeckPalette.dark.brandViolet
    private static let blue = ControlDeckPalette.dark.brandBlue
    private static let cyan = ControlDeckPalette.dark.cpu

    /// Corners stay pinned so the edges never show through; edge midpoints slide along their own
    /// edge and the centre wanders in a small Lissajous loop.
    private static func points(t: TimeInterval) -> [SIMD2<Float>] {
        func wave(_ period: Double, _ amplitude: Double, phase: Double = 0) -> Float {
            Float(sin(t * 2 * .pi / period + phase) * amplitude)
        }
        return [
            [0, 0], [0.5 + wave(11, 0.18), 0], [1, 0],
            [0, 0.5 + wave(13, 0.16, phase: 1)], [0.5 + wave(9, 0.12), 0.55 + wave(7, 0.1)], [1, 0.5 + wave(12, 0.16, phase: 2)],
            [0, 1], [0.5 + wave(10, 0.2, phase: 3), 1], [1, 1],
        ]
    }

    /// Row-major 3×3. Violet across the top so the light reads as rising from below; the
    /// bottom-centre sun breathes, which is what makes the reference feel alive.
    @available(macOS 15.0, *)
    private static func colors(t: TimeInterval) -> [Color] {
        let breathe = 0.5 + 0.5 * sin(t * 2 * .pi / 6)
        let sun = cyan.mix(with: blue, by: 0.35 * (1 - breathe))
        return [
            violet, violet, violet,
            violet, blue, violet,
            blue, sun, cyan.mix(with: blue, by: 0.5),
        ]
    }

    /// macOS 14 has no `MeshGradient`: a blurred sun drifting over the violet, flattened into a
    /// single Metal-backed layer so the blur is computed once per frame on the GPU.
    private func fallback(t: TimeInterval) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let breathe = 0.5 + 0.5 * sin(t * 2 * .pi / 6)
            ZStack {
                Ellipse()
                    .fill(Self.blue)
                    .frame(width: size.width * 1.1, height: size.height * 0.9)
                    .position(x: size.width * (0.5 + 0.12 * sin(t / 9)), y: size.height * 0.95)
                Ellipse()
                    .fill(Self.cyan.opacity(0.75 + 0.25 * breathe))
                    .frame(width: size.width * 0.6, height: size.height * 0.5)
                    .position(x: size.width * (0.5 + 0.1 * sin(t / 7 + 1)), y: size.height * 1.02)
            }
            .blur(radius: size.width * 0.12)
            .drawingGroup()
        }
        // Outside the blur, so the edges stay solid instead of fading to transparent.
        .background(Self.violet)
    }

    /// The reference's entrance: a feathered edge sweeping up from the bottom.
    private var riseMask: some View {
        GeometryReader { proxy in
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: proxy.size.height * 1.35)
                .offset(y: proxy.size.height * (1 - rise * 1.35))
        }
    }
}

#Preview {
    AnimatedMeshGradientView().frame(width: 320, height: 210)
}
