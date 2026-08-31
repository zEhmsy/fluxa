import FluxaCore
import SwiftUI

// MARK: - CustomizeAlertThresholdsSection

/// The three seeded alert toggles. Creating, deleting, and editing arbitrary thresholds is a
/// separate feature; this section only enables the configured records and exposes delivery status.
struct CustomizeAlertThresholdsSection: View {
    let settings: AppSettings
    let permissions: PermissionsService

    @Environment(\.fluxaVisualStyle) private var visualStyle

    private var isCyber: Bool { visualStyle != .classic }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }

    var body: some View {
        ForEach(settings.alertThresholds) { threshold in
            row(for: threshold)
        }
    }

    private func row(for threshold: AlertThreshold) -> some View {
        HStack(spacing: 10) {
            Image(systemName: threshold.metricID.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(threshold.isEnabled ? FluxaTheme.orange : Color.secondary)
                .frame(width: 28, height: 28)
                .fluxaModuleChrome(
                    fill: threshold.isEnabled
                        ? FluxaTheme.orange.opacity(0.10)
                        : (isCyber ? palette.recessed : FluxaTheme.elevatedSurface),
                    border: threshold.isEnabled
                        ? FluxaTheme.orange.opacity(isCyber ? 0.30 : 0.20)
                        : (isCyber ? palette.border : FluxaTheme.border),
                    cornerRadius: 7,
                    cut: 7
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(threshold.metricID.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail(for: threshold))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            FluxaStatusBadge(
                text: permissions.notifications.title,
                color: permissions.notifications == .granted ? FluxaTheme.green : FluxaTheme.orange
            )

            Toggle("", isOn: enabledBinding(for: threshold))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(FluxaTheme.orange)
                .disabled(permissions.busyPermission != nil)
                .accessibilityLabel("Enable \(threshold.metricID.title) alert")
        }
        .padding(.vertical, 2)
        .fluxaListRowSurface()
    }

    private func detail(for threshold: AlertThreshold) -> String {
        let boundary = SystemMetric(id: threshold.metricID, value: threshold.limit).displayText
        switch threshold.direction {
        case .above: return "At or above \(boundary) for 30 seconds"
        case .below: return "At or below \(boundary) for 30 seconds"
        }
    }

    private func enabledBinding(for threshold: AlertThreshold) -> Binding<Bool> {
        Binding(
            get: {
                settings.alertThresholds.first { $0.id == threshold.id }?.isEnabled ?? false
            },
            set: { isEnabled in
                guard let index = settings.alertThresholds.firstIndex(where: { $0.id == threshold.id }) else {
                    return
                }
                let wasEnabled = settings.alertThresholds[index].isEnabled
                settings.alertThresholds[index].isEnabled = isEnabled
                if isEnabled && !wasEnabled {
                    Task { await permissions.requestNotifications() }
                }
            }
        )
    }
}
