import Foundation

// MARK: - ThermalSensorReader

/// CPU and GPU die temperatures, read from the HID thermal sensors the SoC publishes.
///
/// **This is the one place in Fluxa that uses a private interface.** macOS exposes no public API for
/// die temperatures: `powermetrics` needs root, and the SMC keys that worked on Intel are not
/// populated on Apple Silicon. What remains is `IOHIDEventSystemClient`, the same mechanism every
/// third-party temperature monitor uses — unsandboxed, no elevated privileges, but undocumented.
///
/// Because it is undocumented, every step is treated as optional: the framework is resolved with
/// `dlopen`/`dlsym` rather than linked (a missing symbol on a future macOS is then a nil reading, not
/// a launch failure), and a machine where nothing matches simply reports no temperatures. The two
/// metrics disappear from the UI; nothing else in the app is affected.
///
/// Sensors are matched once and reused — enumerating the HID service list on every tick would cost
/// far more than reading the values.
final class ThermalSensorReader {

    /// Temperatures in degrees Celsius, each nil when nothing matched.
    ///
    /// `cpu`/`gpu` and `die` are mutually exclusive by construction — see `classify`. A Mac either
    /// labels its sensors per component or it doesn't, and reporting the same die average twice
    /// under two component names would be an invented distinction.
    struct Reading {
        let cpu: Double?
        let gpu: Double?
        let die: Double?
    }

    // MARK: - Private API surface

    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias ClientSetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias ClientCopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias ServiceCopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias ServiceCopyEvent = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias EventGetFloatValue = @convention(c) (CFTypeRef, Int32) -> Double

    /// AppleVendor HID page, temperature-sensor usage — the pair that selects thermal sensors.
    private static let appleVendorPage = 0xff00
    private static let temperatureSensorUsage = 5

    /// kIOHIDEventTypeTemperature, and the field id derived from it the way IOKit composes them
    /// (`type << 16`).
    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    /// Readings outside this band are sensor noise or an unpopulated channel, not a die temperature.
    private static let plausibleRange: ClosedRange<Double> = 1...125

    // MARK: - Resolved symbols

    private struct Symbols {
        let copyEvent: ServiceCopyEvent
        let getFloatValue: EventGetFloatValue
    }

    private var symbols: Symbols?

    /// The event system client, held for the reader's lifetime.
    ///
    /// Not an incidental reference: the client **owns** the service clients below. Letting it go out
    /// of scope after matching tears down its mach port, and the next `CopyEvent` on a now-dangling
    /// service dereferences null inside IOKit's termination callback — a hard crash, not a nil
    /// reading.
    private var client: CFTypeRef?

    /// Matched sensor services, split by component. Built on first use.
    private var cpuSensors: [CFTypeRef] = []
    private var gpuSensors: [CFTypeRef] = []
    private var dieSensors: [CFTypeRef] = []
    private var didAttemptSetup = false

    // MARK: - Reading

    func read() -> Reading {
        if !didAttemptSetup { setUp() }
        guard let symbols else { return Reading(cpu: nil, gpu: nil, die: nil) }

        return Reading(
            cpu: average(of: cpuSensors, symbols: symbols),
            gpu: average(of: gpuSensors, symbols: symbols),
            die: average(of: dieSensors, symbols: symbols)
        )
    }

    /// The die has many sensors and they disagree by a few degrees; the mean is the number that
    /// tracks the component's actual thermal state rather than whichever core happens to be hottest.
    private func average(of sensors: [CFTypeRef], symbols: Symbols) -> Double? {
        var total = 0.0
        var count = 0

        for sensor in sensors {
            guard let event = symbols.copyEvent(sensor, Self.temperatureEventType, 0, 0)?
                .takeRetainedValue() else { continue }
            let value = symbols.getFloatValue(event, Self.temperatureField)
            guard value.isFinite, Self.plausibleRange.contains(value) else { continue }
            total += value
            count += 1
        }

        return count > 0 ? total / Double(count) : nil
    }

    // MARK: - Setup

    private func setUp() {
        didAttemptSetup = true

        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            return
        }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        guard let create = symbol("IOHIDEventSystemClientCreate", as: ClientCreate.self),
              let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: ClientSetMatching.self),
              let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: ClientCopyServices.self),
              let copyProperty = symbol("IOHIDServiceClientCopyProperty", as: ServiceCopyProperty.self),
              let copyEvent = symbol("IOHIDServiceClientCopyEvent", as: ServiceCopyEvent.self),
              let getFloatValue = symbol("IOHIDEventGetFloatValue", as: EventGetFloatValue.self)
        else {
            return
        }

        guard let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        self.client = client

        let matching: CFDictionary = [
            "PrimaryUsagePage": Self.appleVendorPage,
            "PrimaryUsage": Self.temperatureSensorUsage,
        ] as CFDictionary
        _ = setMatching(client, matching)

        guard let services = copyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { return }

        classify(services, copyProperty: copyProperty)
        symbols = Symbols(copyEvent: copyEvent, getFloatValue: getFloatValue)
    }

    /// Sorts the matched sensors by what they measure, using the `Product` name the driver publishes.
    ///
    /// Two naming schemes exist, and which one a Mac uses decides what Fluxa can honestly report:
    ///
    /// - **Per-component** (M1/M2 era): `pACC MTR Temp Sensor0` and `eACC MTR Temp Sensor1` for the
    ///   performance and efficiency clusters, `GPU MTR Temp Sensor3` for the graphics cores. Here CPU
    ///   and GPU are genuinely separable.
    /// - **Unlabelled die** (later SoCs): `PMU tdie1` … `PMU2 tdie10`, dozens of die sensors carrying
    ///   no indication of which block they sit under. Nothing in the data distinguishes CPU from GPU,
    ///   so the only truthful reading is a single die temperature.
    ///
    /// Two names must be excluded from the die average even though they match the HID temperature
    /// usage: `tcal` is a calibration constant that never moves (it would drag the average several
    /// degrees), and `tdev` channels can be unpopulated and report nonsense like -9201 °C — the
    /// latter is also caught by `plausibleRange`, but excluding it here keeps the intent explicit.
    /// Battery and NAND sensors are ignored for the obvious reason that they are not the SoC.
    private func classify(_ services: [CFTypeRef], copyProperty: ServiceCopyProperty) {
        var componentCPU: [CFTypeRef] = []
        var componentGPU: [CFTypeRef] = []
        var dieAverage: [CFTypeRef] = []

        for service in services {
            guard let name = copyProperty(service, "Product" as CFString)?
                .takeRetainedValue() as? String else { continue }
            let upper = name.uppercased()

            // GPU is tested first: "GPU MTR Temp Sensor" would otherwise fall into a looser CPU match.
            if upper.contains("GPU MTR") {
                componentGPU.append(service)
            } else if upper.contains("ACC MTR") || upper.contains("CPU") {
                componentCPU.append(service)
            } else if upper.contains("TDIE"), !upper.contains("TCAL") {
                dieAverage.append(service)
            }
        }

        // Per-component naming wins outright when present; otherwise the die average is all this Mac
        // can say, and it is published as its own metric rather than dressed up as two.
        if !componentCPU.isEmpty || !componentGPU.isEmpty {
            cpuSensors = componentCPU
            gpuSensors = componentGPU
        } else {
            dieSensors = dieAverage
        }
    }
}
