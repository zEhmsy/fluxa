import SwiftUI

// MARK: - Resource Bundle

extension Bundle {
    /// SPM resources live in Fluxa_Fluxa.bundle. In the packaged .app, build.sh
    /// copies it into Contents/Resources (Bundle.module only checks the .app root,
    /// where codesign forbids unsealed content, and the machine-specific .build path).
    /// From `swift run`, resourceURL is the build dir and the bundle sits there too.
    static let fluxaResources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Fluxa_Fluxa.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()
}

// MARK: - FluxaApp

@main
struct FluxaApp: App {

    // MARK: - State

    @State private var settings: AppSettings
    @State private var viewModel: PopoverViewModel

    // NSApplicationDelegateAdaptor MUST only appear here, in the App struct.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - Init

    init() {
        let s = AppSettings()
        let vm = PopoverViewModel(settings: s)
        _settings = State(wrappedValue: s)
        _viewModel = State(wrappedValue: vm)
    }

    // MARK: - Scene

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
                .environment(viewModel)
                .environment(settings)
                .onAppear {
                    appDelegate.viewModel = viewModel
                    viewModel.refreshStates()
                }
        } label: {
            menuBarIcon
        }
        .menuBarExtraStyle(.window)

        // Standalone window for Focus Mode onboarding.
        // A Window scene (not a sheet) so it stays open when the user switches
        // to the Shortcuts app to confirm the import dialog.
        Window("Focus Mode Setup", id: "focus-onboarding") {
            FocusOnboardingView()
                .environment(viewModel)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Dedicated window for the Lid Angle monitor.
        Window("Lid Angle", id: "lid-angle") {
            LidAngleWindowView()
                .environment(viewModel)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    // MARK: - Menu Bar Icon

    @ViewBuilder
    private var menuBarIcon: some View {
        if let image = loadMenuBarIcon() {
            Image(nsImage: image)
        } else {
            Image(systemName: "bolt.circle.fill")
        }
    }

    /// Loads fluxa.icns from the SPM resource bundle and resizes it for the menu bar (18pt).
    private func loadMenuBarIcon() -> NSImage? {
        guard let url = Bundle.fluxaResources.url(forResource: "fluxa", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        let size = NSSize(width: 18, height: 18)
        let resized = NSImage(size: size)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        resized.unlockFocus()
        // Template mode: macOS tints the icon to match the menu bar (light/dark)
        resized.isTemplate = true
        return resized
    }
}
