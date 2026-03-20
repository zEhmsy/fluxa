import Foundation
import IOKit.pwr_mgt

// MARK: - KeepAwakeService

/// Prevents the display from sleeping using an IOKit power management assertion.
///
/// How it works:
/// - `IOPMAssertionCreateWithName` registers a named assertion with the system power daemon.
/// - While the assertion is active the display will not dim or sleep due to inactivity.
/// - `IOPMAssertionRelease` removes the assertion and restores normal sleep behavior.
///
/// Limitation: This prevents *display* sleep only (`kIOPMAssertionTypeNoDisplaySleep`).
/// Use `kIOPMAssertionTypePreventSystemSleep` if you also want to prevent full system sleep.
@MainActor
final class KeepAwakeService {

    // MARK: - State

    /// IOKit assertion identifier; 0 means no active assertion.
    private var assertionID: IOPMAssertionID = 0

    /// Whether the Keep Awake assertion is currently active.
    var isActive: Bool { assertionID != 0 }

    // MARK: - Lifecycle

    deinit {
        // Ensure assertion is released even if the service is deallocated unexpectedly.
        // Note: deinit is not @MainActor-isolated, but IOPMAssertionRelease is thread-safe.
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
        }
    }

    // MARK: - Public API

    /// Creates an IOKit power management assertion to prevent display sleep.
    func activate() throws {
        guard assertionID == 0 else { return } // Already active

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Fluxa Keep Awake — user requested" as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            assertionID = 0
            throw FluxaError.ioKitFailure(result)
        }
    }

    /// Releases the IOKit assertion, allowing normal sleep behavior to resume.
    func deactivate() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    // MARK: - App Lifecycle

    /// Call from applicationWillTerminate to ensure clean assertion release.
    func cleanup() {
        deactivate()
    }
}
