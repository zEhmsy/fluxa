import AppKit
import Observation

// MARK: - WeightUnit

/// Display unit for the trackpad scale readout.
enum WeightUnit: String, CaseIterable, Identifiable {
    case grams
    case ounces

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .grams:  return "g"
        case .ounces: return "oz"
        }
    }

    /// Converts a value in grams into this unit.
    func value(fromGrams grams: Double) -> Double {
        switch self {
        case .grams:  return grams
        case .ounces: return grams / 28.349523125
        }
    }

    /// Decimal places used when formatting a value in this unit.
    var fractionDigits: Int {
        switch self {
        case .grams:  return 1
        case .ounces: return 2
        }
    }
}

// MARK: - MultitouchBridge

/// Minimal runtime binding to the private MultitouchSupport framework.
///
/// The framework is loaded with `dlopen` rather than linked: the binary only exists
/// inside the dyld shared cache (there is no linkable stub in the SDK), and a missing
/// or changed symbol then degrades to "unavailable" instead of failing to launch.
///
/// Touch records are decoded by explicit byte offsets instead of a mirrored Swift
/// struct, because Swift makes no guarantee about matching C field layout. The layout
/// below was verified on this hardware (24×18 sensor): a resting finger reports
/// `pressure` in whole grams, position normalised to 0…1, and state 4 while touching.
///
///     off  0  int32  frame          off 48  float  total     (capacitance)
///     off  8  double timestamp      off 52  float  pressure  (GRAMS)
///     off 16  int32  identifier     off 56  float  angle
///     off 20  int32  state          off 60  float  majorAxis
///     off 24  int32  fingerId       off 64  float  minorAxis
///     off 28  int32  handId         off 68  MTVector absolutePosition
///     off 32  MTVector normalized   off 84  int32  field14
///                                   off 88  int32  field15
///                                   off 92  float  density
///     stride 96
private enum MultitouchBridge {

    static let touchStride = 96
    static let offsetState = 20
    static let offsetPosX = 32
    static let offsetPosY = 36
    static let offsetTotal = 48
    static let offsetPressure = 52

    /// `MTTouchState` value meaning the finger is in full contact with the surface.
    static let stateTouching: Int32 = 4

    typealias DeviceRef = UnsafeMutableRawPointer
    typealias FrameCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Void

    private typealias FnIsAvailable = @convention(c) () -> Bool
    private typealias FnCreateDefault = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias FnStart = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    private typealias FnDevice = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias FnRegister = @convention(c) (UnsafeMutableRawPointer?, FrameCallback) -> Void

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_LAZY
    )

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle else { return nil }
        return dlsym(handle, name)
    }

    /// True when the framework loaded and reports a usable multitouch device.
    static var isSupported: Bool {
        guard let fn = symbol("MTDeviceIsAvailable") else { return false }
        return unsafeBitCast(fn, to: FnIsAvailable.self)()
    }

    /// Opens the built-in trackpad and starts delivering contact frames to `callback`.
    /// Returns the device handle, or nil if any step is unavailable.
    static func startDevice(callback: @escaping FrameCallback) -> DeviceRef? {
        guard isSupported,
              let createFn = symbol("MTDeviceCreateDefault"),
              let registerFn = symbol("MTRegisterContactFrameCallback"),
              let startFn = symbol("MTDeviceStart"),
              let device = unsafeBitCast(createFn, to: FnCreateDefault.self)()
        else { return nil }

        unsafeBitCast(registerFn, to: FnRegister.self)(device, callback)
        guard unsafeBitCast(startFn, to: FnStart.self)(device, 0) == 0 else {
            release(device)
            return nil
        }
        return device
    }

    /// Stops the device and releases it. Safe to call with a device that never started.
    static func stopDevice(_ device: DeviceRef, callback: @escaping FrameCallback) {
        if let fn = symbol("MTUnregisterContactFrameCallback") {
            unsafeBitCast(fn, to: FnRegister.self)(device, callback)
        }
        if let fn = symbol("MTDeviceStop") {
            _ = unsafeBitCast(fn, to: FnStart.self)(device, 0)
        }
        release(device)
    }

    private static func release(_ device: DeviceRef) {
        guard let fn = symbol("MTDeviceRelease") else { return }
        unsafeBitCast(fn, to: FnDevice.self)(device)
    }

    /// Decodes one contact frame into the force reading of the dominant touch.
    /// Returns nil when no finger is in contact, or when the decoded values fail
    /// the plausibility check (which would mean the private layout has changed).
    static func decodeFrame(_ touches: UnsafeMutableRawPointer?, count: Int32) -> Double? {
        guard let touches, count > 0 else { return nil }

        var bestTotal: Float = -1
        var bestPressure: Float = 0

        for index in 0..<Int(count) {
            let record = touches.advanced(by: index * touchStride)
            let state = record.loadUnaligned(fromByteOffset: offsetState, as: Int32.self)
            let posX = record.loadUnaligned(fromByteOffset: offsetPosX, as: Float.self)
            let posY = record.loadUnaligned(fromByteOffset: offsetPosY, as: Float.self)
            let total = record.loadUnaligned(fromByteOffset: offsetTotal, as: Float.self)
            let pressure = record.loadUnaligned(fromByteOffset: offsetPressure, as: Float.self)

            // Layout sanity check at the system boundary: a real record has a state in
            // 0…7, a normalised position inside the surface, and a finite force.
            guard (0...7).contains(state),
                  (-0.2...1.2).contains(posX), (-0.2...1.2).contains(posY),
                  total.isFinite, pressure.isFinite,
                  (0...20_000).contains(pressure)
            else { return nil }

            guard state == stateTouching, total > bestTotal else { continue }
            bestTotal = total
            bestPressure = pressure
        }

        return bestTotal >= 0 ? Double(bestPressure) : nil
    }
}

// MARK: - Callback plumbing

/// A C function pointer cannot capture context, so the live service is reachable
/// through this global. Written on the main actor, read on the multitouch thread.
private nonisolated(unsafe) weak var activeService: TrackpadWeightService?

private let frameCallback: MultitouchBridge.FrameCallback = { _, touches, count, _, _ in
    let grams = MultitouchBridge.decodeFrame(touches, count: count)
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            activeService?.ingest(grams: grams)
        }
    }
}

// MARK: - TrackpadWeightService

/// Turns the Force Touch trackpad into a scale for small objects.
///
/// The trackpad's strain gauges measure the **total** force applied to the surface,
/// but the hardware only reports that force while it also detects a capacitive touch.
/// An inert object is not capacitive, so it cannot be weighed on its own: the user
/// rests a finger on the trackpad as lightly as possible (the finger enables the
/// reading) and places the object anywhere on the surface. The force delta is the
/// object's weight — already expressed in grams by the hardware, so no calibration
/// constant is involved.
///
/// The finger's own force is never stable, so the zero is not captured by waiting for
/// a steady reading. Instead the baseline tracks the live value while the pad is
/// "quiet", and freezes retroactively at the pre-jump sample the moment a sudden rise
/// betrays an object landing. That removes the need to press any button while holding
/// a finger down.
@Observable
@MainActor
final class TrackpadWeightService {

    // MARK: - Observable State

    /// True when the multitouch framework and a trackpad device are usable.
    private(set) var isAvailable: Bool = MultitouchBridge.isSupported

    /// True while the device is running and delivering frames.
    private(set) var isRunning = false

    /// True while a finger is in contact with the trackpad.
    private(set) var hasContact = false

    /// Raw force reported by the hardware, in grams (finger included).
    private(set) var rawGrams: Double = 0

    /// Measured weight of the object in grams — raw force minus the frozen baseline.
    private(set) var weightGrams: Double = 0

    /// True once a placement has been detected and the baseline is frozen.
    private(set) var hasObject = false

    /// True when the recent readings agree closely enough to trust the number.
    private(set) var isStable = false

    /// Highest weight observed since the current placement began.
    private(set) var peakGrams: Double = 0

    /// True when contact frames arrived but the force channel stayed flat at zero,
    /// which means the trackpad has no Force Touch sensor.
    private(set) var lacksForceSensor = false

    // MARK: - Tuning

    /// Rise across the detection window that counts as "an object was placed".
    private static let placementJumpGrams: Double = 4

    /// Samples kept for jump detection (~0.3 s at the observed ~23 Hz frame rate).
    private static let historySize = 7

    /// Spread below which the reading is considered settled.
    private static let stabilityToleranceGrams: Double = 1.5

    /// Consecutive near-zero readings after which a removed object is assumed.
    private static let removalFrames = 12

    // MARK: - Private

    private var device: MultitouchBridge.DeviceRef?
    private var history: [Double] = []
    private var baselineGrams: Double = 0
    private var nearZeroCount = 0
    private var contactFramesSeen = 0
    private var nonZeroForceSeen = false

    // MARK: - Lifecycle

    /// Starts listening to trackpad contact frames.
    func start() {
        guard !isRunning else { return }
        resetMeasurement()
        activeService = self
        guard let handle = MultitouchBridge.startDevice(callback: frameCallback) else {
            isAvailable = false
            activeService = nil
            return
        }
        device = handle
        isAvailable = true
        isRunning = true
    }

    /// Stops the device and clears all per-session state.
    func stop() {
        if let device {
            MultitouchBridge.stopDevice(device, callback: frameCallback)
            self.device = nil
        }
        if activeService === self { activeService = nil }
        isRunning = false
        hasContact = false
        resetMeasurement()
    }

    // MARK: - Frame Intake

    /// Consumes one decoded frame. `grams` is nil when no finger is touching.
    func ingest(grams: Double?) {
        guard let grams else {
            // Finger lifted: the reading is meaningless, start over.
            hasContact = false
            resetMeasurement()
            return
        }

        hasContact = true
        rawGrams = grams
        contactFramesSeen += 1
        if grams > 0 { nonZeroForceSeen = true }
        // A Force Touch trackpad reports a non-zero force almost immediately.
        lacksForceSensor = !nonZeroForceSeen && contactFramesSeen > 30

        history.append(grams)
        if history.count > Self.historySize { history.removeFirst() }

        if hasObject {
            updateMeasurement(grams: grams)
        } else {
            trackBaseline(grams: grams)
        }
    }

    /// Before a placement: the baseline follows the live force, so the readout sits at
    /// zero no matter how much the finger wanders. A sudden rise across the window is
    /// read as an object landing, and the baseline is frozen at the oldest pre-jump
    /// sample rather than at the current (already loaded) one.
    private func trackBaseline(grams: Double) {
        weightGrams = 0
        peakGrams = 0
        isStable = false

        guard history.count == Self.historySize, let oldest = history.first else {
            baselineGrams = grams
            return
        }

        if grams - oldest >= Self.placementJumpGrams {
            baselineGrams = oldest
            hasObject = true
            nearZeroCount = 0
            updateMeasurement(grams: grams)
        } else {
            baselineGrams = grams
        }
    }

    /// After a placement: report the delta, track the peak, and notice a removal.
    private func updateMeasurement(grams: Double) {
        weightGrams = max(0, grams - baselineGrams)
        peakGrams = max(peakGrams, weightGrams)

        if history.count == Self.historySize,
           let low = history.min(), let high = history.max() {
            isStable = (high - low) <= Self.stabilityToleranceGrams
        }

        // The object was taken off again — go back to following the finger.
        if weightGrams < Self.placementJumpGrams / 2 {
            nearZeroCount += 1
            if nearZeroCount >= Self.removalFrames { resetMeasurement() }
        } else {
            nearZeroCount = 0
        }
    }

    // MARK: - Manual Controls

    /// Forces the current reading to become the new zero. Useful when the object was
    /// placed too gradually for the jump detector, or to weigh a second item on top.
    func zero() {
        guard hasContact else { return }
        baselineGrams = rawGrams
        hasObject = true
        weightGrams = 0
        peakGrams = 0
        nearZeroCount = 0
    }

    /// Discards the current measurement and returns to baseline-following mode.
    func resetMeasurement() {
        history.removeAll(keepingCapacity: true)
        baselineGrams = rawGrams
        weightGrams = 0
        peakGrams = 0
        hasObject = false
        isStable = false
        nearZeroCount = 0
        contactFramesSeen = 0
        nonZeroForceSeen = false
        lacksForceSensor = false
    }
}
