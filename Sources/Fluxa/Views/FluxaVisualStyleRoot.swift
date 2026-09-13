import SwiftUI

/// Defers the observable settings read until SwiftUI evaluates a scene's root view. Passing the
/// settings object through `FluxaApp.body` therefore does not make the app's scene graph observe it.
private struct FluxaVisualStyleRootModifier: ViewModifier {
    let settings: AppSettings

    func body(content: Content) -> some View {
        content.environment(\.fluxaVisualStyle, settings.visualStyle)
    }
}

extension View {
    func fluxaVisualStyle(from settings: AppSettings) -> some View {
        modifier(FluxaVisualStyleRootModifier(settings: settings))
    }
}
