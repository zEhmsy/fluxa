import Foundation
import Observation
import Sparkle

/// One updater for the entire Direct app lifetime. Sparkle owns consent, scheduling,
/// preferences, verification and installation; this service only bridges state to SwiftUI.
@Observable
@MainActor
final class UpdateService: NSObject, SPUUpdaterDelegate {
    private(set) var isStarted = false
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var sessionInProgress = false
    private(set) var lastUpdateCheckDate: Date?
    private(set) var configurationError: String?
    private(set) var lastError: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var didAttemptStart = false

    var statusDescription: String {
        if let configurationError { return configurationError }
        if !isStarted { return "Starting the updater…" }
        if sessionInProgress { return "An update check or installation is in progress." }
        if let lastError { return lastError }
        if let lastUpdateCheckDate {
            return "Last checked \(lastUpdateCheckDate.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Check for a new version of Fluxa Direct."
    }

    /// Called by AppDelegate at launch, never by a transient popover task.
    func start() {
        guard !didAttemptStart else { return }
        didAttemptStart = true

        if let error = Self.configurationProblem(in: .main) {
            configurationError = error
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            },
            updater.observe(\.sessionInProgress, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.synchronizeState() }
            }
        ]

        do {
            // Catch configuration failures without presenting an unsolicited alert at launch.
            try updater.start()
            isStarted = true
            synchronizeState()
        } catch {
            configurationError = "The updater could not start: \(error.localizedDescription)"
            observations.removeAll()
            self.controller = nil
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        lastError = nil
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isStarted, let updater = controller?.updater else { return }
        // Only write in response to an explicit user action. No duplicate AppSettings key.
        updater.automaticallyChecksForUpdates = enabled
        synchronizeState()
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        let nsError = error as NSError?
        if let nsError,
           !(nsError.domain == SUSparkleErrorDomain &&
             [SUError.noUpdateError, SUError.installationCanceledError]
                .contains(where: { Int($0.rawValue) == nsError.code })) {
            lastError = nsError.localizedDescription
        } else {
            lastError = nil
        }
        synchronizeState()
    }

    private func synchronizeState() {
        guard isStarted, let updater = controller?.updater else { return }
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        sessionInProgress = updater.sessionInProgress
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }

    private static func configurationProblem(in bundle: Bundle) -> String? {
        guard bundle.bundleURL.pathExtension == "app" else {
            return "Updates are available from the packaged Fluxa app."
        }
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URLComponents(string: feed),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil,
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let data = Data(base64Encoded: key), data.count == 32 else {
            return "Updates are not configured in this development build."
        }
        return nil
    }
}
