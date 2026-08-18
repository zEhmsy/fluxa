import SwiftUI

// MARK: - TrackpadScaleWindowView

/// Dedicated window that turns the Force Touch trackpad into a scale for small objects.
///
/// The trackpad reports force only while it also senses a capacitive touch, so the
/// finger is what unlocks the reading — the object itself rests on the trackpad, not
/// on the finger. The zero is captured automatically the moment the object lands.
struct TrackpadScaleWindowView: View {

    @Environment(PopoverViewModel.self) private var viewModel
    @Environment(AppSettings.self) private var settings

    @State private var unit: WeightUnit = .grams

    private var scale: TrackpadWeightService { viewModel.trackpadWeight }

    var body: some View {
        VStack(spacing: 14) {
            FluxaToolHeader(
                title: "Trackpad Scale",
                subtitle: "Force Touch precision scale",
                systemImage: "scalemass",
                tint: FluxaTheme.teal
            )

            if scale.isAvailable {
                readout
                steps
            } else {
                FluxaToolCard {
                    unavailableView
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(width: 400, height: 500)
        .background(FluxaTheme.panelBackground)
        .onAppear {
            unit = settings.trackpadScaleUnit
            scale.start()
        }
        .onDisappear { scale.stop() }
        .onChange(of: unit) { _, new in settings.trackpadScaleUnit = new }
    }

    // MARK: - Readout

    private var readout: some View {
        FluxaToolCard {
            VStack(spacing: 10) {
                HStack {
                    FluxaSectionLabel(title: "Live weight")

                    Picker("Unit", selection: $unit) {
                        ForEach(WeightUnit.allCases) { option in
                            Text(option.symbol).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 82)
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(formatted(scale.weightGrams))
                        .font(.system(size: 50, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(readoutColor)
                    Text(unit.symbol)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .animation(.easeOut(duration: 0.15), value: scale.weightGrams)

                statusPill

                Text(peakText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    private var readoutColor: Color {
        if !scale.hasObject { return .secondary }
        return scale.isStable ? FluxaTheme.green : FluxaTheme.orange
    }

    private var statusPill: some View {
        FluxaStatusBadge(text: statusText, color: statusColor)
    }

    private var statusText: String {
        if scale.lacksForceSensor { return "No Force Touch sensor on this trackpad" }
        if !scale.hasContact { return "Rest a finger on the trackpad" }
        if !scale.hasObject { return "Ready — now place the object" }
        return scale.isStable ? "Stable" : "Settling…"
    }

    private var statusColor: Color {
        if scale.lacksForceSensor { return FluxaTheme.red }
        if !scale.hasContact { return .secondary }
        if !scale.hasObject { return FluxaTheme.blue }
        return scale.isStable ? FluxaTheme.green : FluxaTheme.orange
    }

    private var peakText: String {
        guard scale.hasObject && scale.peakGrams > 0 else {
            return "Peak weight will appear here"
        }
        return "Peak \(formatted(scale.peakGrams)) \(unit.symbol)"
    }

    // MARK: - Instructions

    private var steps: some View {
        FluxaToolCard {
            VStack(alignment: .leading, spacing: 10) {
                FluxaSectionLabel(title: "How to measure")

                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Rest one finger lightly on the trackpad.")
                    step(2, "Keep your finger pressure as steady as possible.")
                    step(3, "Place the object beside your finger — Fluxa zeroes automatically.")
                }

                FluxaPanelDivider(horizontalInset: 0)

                controls
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(number)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(FluxaTheme.accentFill))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Zero here") { scale.zero() }
                    .buttonStyle(FluxaButtonStyle(tint: FluxaTheme.blue))
                    .disabled(!scale.hasContact)
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Use the current force as the new zero — for objects placed too "
                          + "gradually to be detected, or to weigh a second item on top")

                Button("Restart") { scale.resetMeasurement() }
                    .buttonStyle(FluxaButtonStyle(tint: FluxaTheme.teal))
                    .help("Discard this measurement and wait for a new object")

                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "info.circle")
                    .foregroundStyle(FluxaTheme.accent)
                    .accessibilityHidden(true)
                Text("For metal objects, place a sheet of paper underneath. Raw force: "
                     + "\(Int(scale.rawGrams)) g.")
            }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Unavailable

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(FluxaTheme.orange)
                .frame(width: 56, height: 56)
                .background(
                    FluxaTheme.orange.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            Text("Trackpad Scale Not Available")
                .font(.system(size: 14, weight: .semibold))
            Text("This needs the pressure data of a built-in Force Touch trackpad "
                 + "(MacBook Pro 2015 and later, MacBook 2016 and later).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Formatting

    private func formatted(_ grams: Double) -> String {
        String(format: "%.\(unit.fractionDigits)f", unit.value(fromGrams: grams))
    }
}
