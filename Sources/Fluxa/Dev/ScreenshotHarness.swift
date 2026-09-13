import AppKit
import SwiftUI
import FluxaCore

@MainActor
enum ScreenshotHarness {

    struct CaptureItem {
        let filename: String
        let width: CGFloat
        let isTitled: Bool
        let title: String
        let buildView: (PopoverViewModel, AppSettings) -> AnyView
    }

    static func run(with viewModel: PopoverViewModel, settings: AppSettings, outputDir: String) {
        Task { @MainActor in
            await performCapture(with: viewModel, settings: settings, outputDir: outputDir)
        }
    }

    private static func performCapture(
        with viewModel: PopoverViewModel,
        settings: AppSettings,
        outputDir: String
    ) async {
        print("[ScreenshotHarness] Starting screenshot generation to: \(outputDir)")

        // Configure AppSettings
        settings.visualStyle = .cyberDark
        settings.hiddenActionIDs = []
        settings.actionOrder = [
            .keepAwake,
            .urlCleaner,
            .colorPicker,
            .screenClean,
            .lockKeyboard,
            .audioOutput,
            .micMute,
            .killProcess,
            .focusMode,
            .darkMode,
            .desktopIcons,
            .hiddenFiles,
            .dockAutohide,
            .screenSaver,
            .bluetoothAudio,
            .lidAngle,
            .trackpadScale
        ]
        settings.systemMetricIDs = [
            SystemMetricID.cpuUsage.rawValue,
            SystemMetricID.memoryUsage.rawValue,
            SystemMetricID.dieTemperature.rawValue
        ]
        settings.usageMetricIDs = [
            "claude.session",
            "codex.weekly"
        ]

        seedAll(viewModel: viewModel)

        let items: [CaptureItem] = [
            CaptureItem(
                filename: "fluxa-customize.png",
                width: 480,
                isTitled: false,
                title: "Customize Fluxa",
                buildView: { vm, set in
                    AnyView(
                        CustomizeView(selectedTab: .general, onDone: {})
                            .environment(vm)
                            .environment(set)
                            .fluxaVisualStyle(from: set)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                }
            ),
            CaptureItem(
                filename: "fluxa-customize-actions.png",
                width: 480,
                isTitled: false,
                title: "Customize Fluxa",
                buildView: { vm, set in
                    AnyView(
                        CustomizeView(selectedTab: .actions, onDone: {})
                            .environment(vm)
                            .environment(set)
                            .fluxaVisualStyle(from: set)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                }
            ),
            CaptureItem(
                filename: "fluxa-customize-system.png",
                width: 480,
                isTitled: false,
                title: "Customize Fluxa",
                buildView: { vm, set in
                    AnyView(
                        CustomizeView(selectedTab: .system, onDone: {})
                            .environment(vm)
                            .environment(set)
                            .fluxaVisualStyle(from: set)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                }
            ),
            CaptureItem(
                filename: "fluxa-customize-agents.png",
                width: 480,
                isTitled: false,
                title: "Customize Fluxa",
                buildView: { vm, set in
                    AnyView(
                        CustomizeView(selectedTab: .agents, onDone: {})
                            .environment(vm)
                            .environment(set)
                            .fluxaVisualStyle(from: set)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                }
            ),
            CaptureItem(
                filename: "fluxa-customize-updates.png",
                width: 480,
                isTitled: false,
                title: "Customize Fluxa",
                buildView: { vm, set in
                    AnyView(
                        CustomizeView(selectedTab: .updates, onDone: {})
                            .environment(vm)
                            .environment(set)
                            .fluxaVisualStyle(from: set)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                }
            ),
            CaptureItem(
                filename: "fluxa-about.png",
                width: 480,
                isTitled: false,
                title: "About Fluxa",
                buildView: { vm, set in
                    AnyView(
                        InfoView(onDone: {})
                            .environment(vm)
                            .environment(set)
                            .fluxaVisualStyle(from: set)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                }
            ),
            CaptureItem(
                filename: "fluxa-menu.png",
                width: FluxaTheme.panelWidth,
                isTitled: false,
                title: "Fluxa",
                buildView: { vm, set in
                    AnyView(
                        ControlDeckDashboardView(
                            style: .cyberDark,
                            onCustomize: {},
                            onAbout: {},
                            closePopover: nil
                        )
                        .environment(vm)
                        .environment(set)
                        .fluxaVisualStyle(from: set)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                }
            ),
            CaptureItem(
                filename: "fluxa-system-dashboard.png",
                width: 700,
                isTitled: true,
                title: "System Dashboard",
                buildView: { vm, set in
                    AnyView(
                        SystemStatsWindowView()
                            .environment(vm)
                            .environment(set)
                            .fluxaVisualStyle(from: set)
                    )
                }
            ),
            CaptureItem(
                filename: "fluxa-agent-usage.png",
                width: 480,
                isTitled: true,
                title: "Agent Usage",
                buildView: { vm, set in
                    AnyView(
                        AgentUsageWindowView()
                            .environment(vm)
                            .environment(set)
                            .fluxaVisualStyle(from: set)
                    )
                }
            )
        ]

        for item in items {
            seedAll(viewModel: viewModel)
            await capture(item: item, viewModel: viewModel, settings: settings, outputDir: outputDir)
        }

        print("[ScreenshotHarness] All screenshots successfully generated!")
        NSApp.terminate(nil)
    }

    private static func seedAll(viewModel: PopoverViewModel) {
        viewModel.systemStats.seedSampleDataForScreenshots()
        viewModel.peripheralBattery.seedSampleDataForScreenshots()
        viewModel.agentUsage.seedSampleDataForScreenshots()
        viewModel.githubProfile.seedSampleDataForScreenshots()
    }

    private static func capture(
        item: CaptureItem,
        viewModel: PopoverViewModel,
        settings: AppSettings,
        outputDir: String
    ) async {
        let view = item.buildView(viewModel, settings)
        let hostingView = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: item.width, height: 400),
            styleMask: item.isTitled ? [.titled, .closable, .miniaturizable] : [.borderless],
            backing: .buffered,
            defer: false
        )

        if item.isTitled {
            window.title = item.title
        } else {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
        }

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let finalSize = CGSize(width: item.width, height: max(100, fittingSize.height))

        window.setContentSize(finalSize)
        hostingView.frame = NSRect(origin: .zero, size: finalSize)
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Re-seed to override any onAppear side effects
        seedAll(viewModel: viewModel)

        // Wait for rendering pass
        try? await Task.sleep(for: .milliseconds(500))

        let destination = (outputDir as NSString).appendingPathComponent(item.filename)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-o", "-l\(window.windowNumber)", destination]
        try? task.run()
        task.waitUntilExit()

        print("[ScreenshotHarness] Captured \(item.filename) (status: \(task.terminationStatus))")

        window.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(100))
    }
}
