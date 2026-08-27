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
                .environment(\.fluxaVisualStyle, settings.visualStyle)
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
                .environment(\.fluxaVisualStyle, settings.visualStyle)
                .registersFluxaWindow(id: "focus-onboarding")
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Dedicated window for the Lid Angle monitor.
        Window("Lid Angle", id: "lid-angle") {
            LidAngleWindowView()
                .environment(viewModel)
                .environment(\.fluxaVisualStyle, settings.visualStyle)
                .registersFluxaWindow(id: "lid-angle")
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Dedicated window for the Trackpad Scale.
        Window("Trackpad Scale", id: "trackpad-scale") {
            TrackpadScaleWindowView()
                .environment(viewModel)
                .environment(settings)
                .environment(\.fluxaVisualStyle, settings.visualStyle)
                .registersFluxaWindow(id: "trackpad-scale")
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Live system history, opened by clicking the popover's system strip.
        Window("System Dashboard", id: "system-stats") {
            SystemStatsWindowView()
                .environment(viewModel)
                .environment(settings)
                .environment(\.fluxaVisualStyle, settings.visualStyle)
                .registersFluxaWindow(id: "system-stats")
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Agent quota charts, opened by clicking the popover's usage strip.
        Window("Agent Usage", id: "agent-usage") {
            AgentUsageWindowView()
                .environment(viewModel)
                .environment(settings)
                .environment(\.fluxaVisualStyle, settings.visualStyle)
                .registersFluxaWindow(id: "agent-usage")
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    // MARK: - Menu Bar Icon

    /// A reading for each metric the user sent to the menu bar in Customize. When the list is empty,
    /// the Fluxa mark is used as a compact fallback. Reading the observable services here is what
    /// makes the strip refresh itself: a new value re-renders the label and status item.
    @ViewBuilder
    private var menuBarIcon: some View {
        if let image = MenuBarStripRenderer.image(segments: menuBarSegments) {
            Image(nsImage: image)
        } else {
            Image(systemName: "bolt.circle.fill")
        }
    }

    private var menuBarSegments: [MenuBarStripRenderer.Segment] {
        MenuBarStripRenderer.combinedSegments(
            system: viewModel.systemStats.selectedMetrics(ids: settings.systemMenuBarMetricIDs),
            agents: viewModel.agentUsage.selectedMetrics(ids: settings.usageMenuBarMetricIDs),
            limit: AppSettings.maxMenuBarMetrics
        )
    }
}
