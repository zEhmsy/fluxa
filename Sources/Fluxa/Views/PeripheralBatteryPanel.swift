import FluxaCore
import SwiftUI

// MARK: - PeripheralBatteryPanel

/// Connected accessory batteries shown as a variable-length dashboard list.
struct PeripheralBatteryPanel: View {
    let devices: [PeripheralBatteryReading]

    @Environment(\.fluxaVisualStyle) private var visualStyle

    private var isCyber: Bool { visualStyle.isCyber }
    private var palette: ControlDeckPalette { .resolve(visualStyle) }

    private var accent: Color {
        visualStyle.isClassic ? FluxaTheme.green : palette.battery
    }

    var body: some View {
        FluxaToolCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magicmouse")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("Peripherals")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("Connected accessories")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isCyber ? palette.tertiaryText : Color.secondary)
                }

                if devices.isEmpty {
                    Text("No connected accessories reporting battery.")
                        .font(.system(size: 11))
                        .foregroundStyle(isCyber ? palette.secondaryText : Color.secondary)
                        .frame(minHeight: 20)
                } else {
                    VStack(spacing: 6) {
                        ForEach(devices) { device in
                            HStack(spacing: 8) {
                                Image(systemName: iconName(for: device.name))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(accent.opacity(0.85))
                                    .frame(width: 14)
                                Text(device.name)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if device.isCharging {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(FluxaTheme.teal)
                                        .accessibilityLabel("Charging")
                                }
                                Text("\(device.level)%")
                                    .monospacedDigit()
                                    .foregroundStyle(accent)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .frame(minHeight: 20)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private func iconName(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpod") { return "airpodspro" }
        if lower.contains("headphone") || lower.contains("headset") || lower.contains("buds") { return "headphones" }
        if lower.contains("mouse") { return "magicmouse" }
        if lower.contains("trackpad") { return "trackpad" }
        if lower.contains("keyboard") || lower.contains("key") { return "keyboard" }
        return "wave.3.right"
    }
}
