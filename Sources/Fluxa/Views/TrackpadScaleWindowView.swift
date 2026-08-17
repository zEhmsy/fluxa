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
            if scale.isAvailable {
                readout
                Divider()
                steps
                Spacer(minLength: 0)
                controls
            } else {
                unavailableView
            }
        }
        .padding(18)
        .frame(width: 340, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            unit = settings.trackpadScaleUnit
            scale.start()
        }
        .onDisappear { scale.stop() }
        .onChange(of: unit) { _, new in settings.trackpadScaleUnit = new }
    }

    // MARK: - Readout

    private var readout: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatted(scale.weightGrams))
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(readoutColor)
                Text(unit.symbol)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .animation(.easeOut(duration: 0.15), value: scale.weightGrams)

            statusPill

            if scale.hasObject && scale.peakGrams > 0 {
                Text("peak \(formatted(scale.peakGrams)) \(unit.symbol)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    private var readoutColor: Color {
        if !scale.hasObject { return .secondary }
        return scale.isStable ? .primary : .orange
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(scale.hasContact ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
    }

    private var statusText: String {
        if scale.lacksForceSensor { return "No Force Touch sensor on this trackpad" }
        if !scale.hasContact { return "Rest a finger on the trackpad" }
        if !scale.hasObject { return "Ready — now place the object" }
        return scale.isStable ? "Stable" : "Settling…"
    }

    // MARK: - Instructions

    private var steps: some View {
        VStack(alignment: .leading, spacing: 7) {
            step(1, "Rest one finger on the trackpad and keep it there — the trackpad "
                  + "only reports force while it senses a touch.")
            step(2, "Press as lightly as you can while staying in contact.")
            step(3, "Place the object on the trackpad, next to your finger. "
                  + "The scale zeroes itself automatically as it lands.")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(number)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Color.yellow.opacity(0.85)))
            Text(text)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Zero here") { scale.zero() }
                    .buttonStyle(FluxaButtonStyle())
                    .disabled(!scale.hasContact)
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Use the current force as the new zero — for objects placed too "
                          + "gradually to be detected, or to weigh a second item on top")

                Button("Restart") { scale.resetMeasurement() }
                    .buttonStyle(FluxaButtonStyle())
                    .help("Discard this measurement and wait for a new object")

                Spacer()

                Picker("", selection: $unit) {
                    ForEach(WeightUnit.allCases) { u in Text(u.symbol).tag(u) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 76)
            }

            Text("Metal objects can register as a finger — put a sheet of paper between "
                 + "the object and the trackpad. Raw force: \(Int(scale.rawGrams)) g.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Unavailable

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Trackpad Scale Not Available")
                .font(.system(size: 14, weight: .medium))
            Text("This needs the pressure data of a built-in Force Touch trackpad "
                 + "(MacBook Pro 2015 and later, MacBook 2016 and later).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Formatting

    private func formatted(_ grams: Double) -> String {
        String(format: "%.\(unit.fractionDigits)f", unit.value(fromGrams: grams))
    }
}
