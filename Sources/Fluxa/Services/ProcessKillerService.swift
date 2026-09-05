import AppKit
import Darwin
import Observation

// MARK: - RunningProcessInfo

/// Display information for a user-facing GUI application that Fluxa can terminate.
struct RunningProcessInfo: Identifiable, Equatable, Sendable {
    let id: pid_t
    let name: String
    let cpuTime: TimeInterval
}

// MARK: - ProcessKillerService

/// Lists the current user's regular GUI applications and terminates a selected app politely,
/// escalating to a force-quit only when it remains alive after the grace period.
@Observable
@MainActor
final class ProcessKillerService {
    private(set) var runningProcesses: [RunningProcessInfo] = []

    /// Rebuilds the list from a fresh `NSWorkspace` snapshot and ranks apps by cumulative CPU time.
    func refresh() {
        let currentPID = NSRunningApplication.current.processIdentifier

        runningProcesses = NSWorkspace.shared.runningApplications
            .enumerated()
            .compactMap { offset, application -> (offset: Int, process: RunningProcessInfo)? in
                let pid = application.processIdentifier
                guard application.activationPolicy == .regular,
                      pid != currentPID,
                      !application.isTerminated,
                      let name = displayName(for: application) else {
                    return nil
                }

                return (
                    offset,
                    RunningProcessInfo(
                        id: pid,
                        name: name,
                        cpuTime: cumulativeCPUTime(for: pid)
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.process.cpuTime != rhs.process.cpuTime {
                    return lhs.process.cpuTime > rhs.process.cpuTime
                }
                return lhs.offset < rhs.offset
            }
            .map(\.process)
    }

    /// Requests a normal app termination, then force-terminates it if it is still alive after 2s.
    func terminate(_ process: RunningProcessInfo) {
        let currentPID = NSRunningApplication.current.processIdentifier
        let pid = process.id
        guard pid != currentPID,
              let application = NSRunningApplication(processIdentifier: pid),
              application.activationPolicy == .regular,
              isProcessAlive(pid) else {
            refresh()
            return
        }

        // 1. Politely request termination
        _ = application.terminate()

        // 2. Poll for up to 2 seconds to allow graceful exit. Escalate to forceTerminate/SIGKILL if still alive.
        Task { [weak self] in
            let deadline = DispatchTime.now() + 2.0
            while Self.isAlive(pid) && DispatchTime.now() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            if Self.isAlive(pid) {
                _ = application.forceTerminate()
                if Self.isAlive(pid) {
                    kill(pid, SIGKILL)
                }
            }

            await MainActor.run {
                self?.refresh()
            }
        }
    }

    private func isProcessAlive(_ pid: pid_t) -> Bool {
        Self.isAlive(pid)
    }

    private static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    // MARK: - Private

    private func displayName(for application: NSRunningApplication) -> String? {
        if let name = application.localizedName, !name.isEmpty {
            return name
        }
        guard let bundleURL = application.bundleURL else { return nil }
        let fallback = bundleURL.deletingPathExtension().lastPathComponent
        return fallback.isEmpty ? nil : fallback
    }

    private func cumulativeCPUTime(for pid: pid_t) -> TimeInterval {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard status == 0 else { return 0 }

        let nanoseconds = Double(usage.ri_user_time) + Double(usage.ri_system_time)
        return nanoseconds / 1_000_000_000
    }
}
