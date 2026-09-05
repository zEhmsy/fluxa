import Foundation

// MARK: - AntigravityLocalServer

/// The pure half of finding the helper process Antigravity runs its own usage panel through.
///
/// Both facts Fluxa needs — where the helper listens, and the token it expects — come from the
/// running process rather than from a fixed port or a file on disk. The port is assigned at launch
/// and differs every run, and taking it from that process's own listening sockets means the request
/// can only reach it: a different program squatting a guessed port is never handed the token.
///
/// Everything here is a pure function over the text the system tools print, so the parsing is
/// testable without a running Antigravity. Spawning them lives in `AntigravityUsageReader`.
package enum AntigravityLocalServer {

    /// A helper process worth talking to.
    package struct Instance: Sendable, Equatable {
        package let pid: Int32
        package let token: String

        package init(pid: Int32, token: String) {
            self.pid = pid
            self.token = token
        }
    }

    private static let executableName = "language_server"

    /// Editors built on the same helper run their own copy. The data directory is what says this
    /// one belongs to Antigravity, so quota is never read from a neighbouring product's session.
    private static let dataDirectoryFlag = "--app_data_dir"
    private static let dataDirectory = "antigravity"
    private static let tokenFlag = "--csrf_token"

    /// Reads `ps -axww -o pid=,command=` output: one process per line, pid first, then the full
    /// command line. Returns the first line that is Antigravity's helper and carries a usable token.
    package static func instance(inProcessTable output: String) -> Instance? {
        for line in output.split(separator: "\n") {
            // Fields are split on runs of whitespace, so `ps` padding the pid column costs nothing.
            let fields = line.split(separator: " ").map(String.init)
            guard fields.count > 2, let pid = Int32(fields[0]), pid > 0 else { continue }
            guard fields[1].hasSuffix("/" + executableName) else { continue }
            guard value(of: dataDirectoryFlag, in: fields) == dataDirectory else { continue }
            guard let token = value(of: tokenFlag, in: fields), isUsableToken(token) else { continue }
            return Instance(pid: pid, token: token)
        }
        return nil
    }

    /// `--flag value`, as the helper is launched. A flag with nothing after it is not a match.
    private static func value(of flag: String, in fields: [String]) -> String? {
        guard let index = fields.firstIndex(of: flag), index + 1 < fields.count else { return nil }
        return fields[index + 1]
    }

    /// The token goes into an HTTP header, so it is checked before use rather than trusted for
    /// where it came from: a value carrying a newline would let anything able to influence that
    /// command line append headers of its own.
    package static func isUsableToken(_ token: String) -> Bool {
        guard !token.isEmpty, token.count <= 256 else { return false }
        return token.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || "-._~".unicodeScalars.contains(scalar)
        }
    }

    /// Reads `lsof -nP -aiTCP -sTCP:LISTEN -p <pid>` output, keeping the loopback ports in the order
    /// reported. Addresses other than `127.0.0.1` are ignored: the helper is only ever asked for
    /// quota over loopback, and a socket bound anywhere else is not one of ours to talk to.
    package static func loopbackPorts(inSocketTable output: String) -> [Int] {
        let prefix = "127.0.0.1:"
        var ports: [Int] = []
        for line in output.split(separator: "\n") {
            for field in line.split(separator: " ") where field.hasPrefix(prefix) {
                guard let port = Int(field.dropFirst(prefix.count)),
                      (1...65535).contains(port),
                      !ports.contains(port)
                else { continue }
                ports.append(port)
            }
        }
        return ports
    }
}
