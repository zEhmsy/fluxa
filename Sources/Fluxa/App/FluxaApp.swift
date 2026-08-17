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

        // Dedicated window for the Trackpad Scale.
        Window("Trackpad Scale", id: "trackpad-scale") {
            TrackpadScaleWindowView()
                .environment(viewModel)
                .environment(settings)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Agent quota charts, opened by clicking the popover's usage strip.
        Window("Agent Usage", id: "agent-usage") {
            AgentUsageWindowView()
                .environment(viewModel)
                .environment(settings)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Customize as a standalone window, NOT a sheet: the MenuBarExtra
        // window auto-dismisses whenever it loses key status, so a sheet
        // attached to it dies on any interaction that moves focus.
        Window("Customize Fluxa", id: "customize") {
            CustomizeView()
                .environment(viewModel)
                .environment(settings)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    // MARK: - Menu Bar Icon

    /// The switch mark, followed by a reading for each agent pinned in Customize. Reading the
    /// observable usage service here is what makes the strip refresh itself: a new percentage
    /// re-renders the label, which re-renders the status item.
    @ViewBuilder
    private var menuBarIcon: some View {
        if let image = MenuBarStripRenderer.image(segments: menuBarSegments) {
            Image(nsImage: image)
        } else {
            Image(systemName: "bolt.circle.fill")
        }
    }

    private var menuBarSegments: [MenuBarStripRenderer.Segment] {
        MenuBarStripRenderer.segments(
            for: viewModel.agentUsage.selectedMetrics(ids: settings.usageMetricIDs)
        )
    }
}
