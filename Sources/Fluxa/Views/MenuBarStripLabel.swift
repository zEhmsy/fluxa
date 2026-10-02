import SwiftUI

/// Keeps live metric observation inside the label view so samples update the strip without
/// invalidating and rebuilding the `MenuBarExtra` scene that owns the status item.
struct MenuBarStripLabel: View {
    let settings: AppSettings
    let viewModel: PopoverViewModel

    // Write-only from here: the monitor reports into `collapsed` and the view model flag, and
    // nothing in the scene body reads either (ticket 18).
    @State private var monitor = MenuBarNotchMonitor()
    @State private var collapsed = false

    var body: some View {
        let full = MenuBarStripRenderer.image(segments: menuBarSegments)
        Group {
            if !collapsed, let full {
                Image(nsImage: full)
            } else if let icon = MenuBarStripRenderer.image(segments: []) {
                Image(nsImage: icon)
            } else {
                Image(systemName: "bolt.circle.fill")
            }
        }
        .onAppear {
            monitor.onChange = { isCollapsed in
                collapsed = isCollapsed
                viewModel.menuBarCollapsedByNotch = isCollapsed
            }
            monitor.update(fullWidth: Double(full?.size.width ?? 0))
            monitor.start()
        }
        .onChange(of: full?.size.width) { _, width in
            monitor.update(fullWidth: Double(width ?? 0))
        }
        .onDisappear { monitor.stop() }
    }

    private var menuBarSegments: [MenuBarStripRenderer.Segment] {
        MenuBarStripRenderer.combinedSegments(
            system: viewModel.systemStats.selectedMetrics(ids: settings.systemMenuBarMetricIDs),
            agents: viewModel.agentUsage.selectedMetrics(ids: settings.usageMenuBarMetricIDs),
            limit: AppSettings.maxMenuBarMetrics
        )
    }
}
