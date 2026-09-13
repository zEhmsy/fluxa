import SwiftUI

/// Keeps live metric observation inside the label view so samples update the strip without
/// invalidating and rebuilding the `MenuBarExtra` scene that owns the status item.
struct MenuBarStripLabel: View {
    let settings: AppSettings
    let viewModel: PopoverViewModel

    var body: some View {
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
