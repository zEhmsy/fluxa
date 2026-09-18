import AppKit
import SwiftUI

/// Defers the observable settings read until SwiftUI evaluates a scene's root view. Passing the
/// settings object through `FluxaApp.body` therefore does not make the app's scene graph observe it.
private struct FluxaVisualStyleRootModifier: ViewModifier {
    let settings: AppSettings

    @ViewBuilder
    func body(content: Content) -> some View {
        let styled = content
            .environment(\.fluxaVisualStyle, settings.visualStyle)
            .preferredColorScheme(resolvedColorScheme)
            .background {
                FluxaAppearanceBridge(style: settings.visualStyle)
                    .frame(width: 0, height: 0)
            }

        if let scheme = resolvedColorScheme {
            styled.environment(\.colorScheme, scheme)
        } else {
            styled
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        switch settings.visualStyle {
        case .classic:                 return nil
        case .classicLight, .cyber:    return .light
        case .classicDark, .cyberDark: return .dark
        }
    }
}

/// Bridges AppKit appearance to match Fluxa's chosen visual style.
/// Ensures that NSWindow, NSHostingView, NSSwitch, NSSegmentedControl, and dynamic NSColors
/// draw with the appropriate appearance regardless of the Mac's system-wide dark/light mode.
struct FluxaAppearanceBridge: NSViewRepresentable {
    let style: FluxaVisualStyle

    func makeNSView(context: Context) -> AppearanceBridgeView {
        AppearanceBridgeView(style: style)
    }

    func updateNSView(_ nsView: AppearanceBridgeView, context: Context) {
        nsView.style = style
        nsView.syncAppearance()
    }

    final class AppearanceBridgeView: NSView {
        var style: FluxaVisualStyle

        init(style: FluxaVisualStyle) {
            self.style = style
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            syncAppearance()
        }

        func syncAppearance() {
            let target: NSAppearance? = switch style {
            case .classic: nil
            case .classicLight, .cyber: NSAppearance(named: .aqua)
            case .classicDark, .cyberDark: NSAppearance(named: .darkAqua)
            }
            if window?.appearance != target {
                window?.appearance = target
            }
            if appearance != target {
                appearance = target
            }
        }
    }
}

extension View {
    func fluxaVisualStyle(from settings: AppSettings) -> some View {
        modifier(FluxaVisualStyleRootModifier(settings: settings))
    }
}
