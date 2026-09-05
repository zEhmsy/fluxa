import Foundation
import Testing
@testable import FluxaCore

// MARK: - Fixtures

/// Shaped like real `ps -axww -o pid=,command=` output, including the column padding `ps` applies
/// to the pid and the neighbouring processes the real table is full of.
private let processTable = """
  501 /sbin/launchd
26107 /Applications/Antigravity.app/Contents/Resources/bin/language_server --standalone \
--override_ide_name antigravity --subclient_type hub --https_server_port 0 \
--csrf_token 8e53559e-3cfa-4040-bfa9-003ac3e5701c --app_data_dir antigravity \
--host_bridge_url=http://127.0.0.1:52578
  912 /usr/libexec/secinitd
"""

/// Shaped like `lsof -nP -aiTCP -sTCP:LISTEN -p <pid>`, header row included.
private let socketTable = """
COMMAND     PID     USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
language_ 26107 giuseppe    7u  IPv4 0x4b51a4293e9b28ea      0t0  TCP 127.0.0.1:52579 (LISTEN)
language_ 26107 giuseppe    8u  IPv4 0x7c719684fad05d34      0t0  TCP 127.0.0.1:52580 (LISTEN)
"""

// MARK: - Process table

@Suite("AntigravityLocalServer.instance")
struct AntigravityInstanceTests {

    @Test("The helper is found among unrelated processes, with its pid and token")
    func findsHelper() throws {
        let instance = try #require(AntigravityLocalServer.instance(inProcessTable: processTable))
        #expect(instance.pid == 26107)
        #expect(instance.token == "8e53559e-3cfa-4040-bfa9-003ac3e5701c")
    }

    @Test("An empty or unrelated process table yields nothing")
    func noHelper() {
        #expect(AntigravityLocalServer.instance(inProcessTable: "") == nil)
        #expect(AntigravityLocalServer.instance(inProcessTable: "  501 /sbin/launchd") == nil)
        #expect(AntigravityLocalServer.instance(inProcessTable: "\n\n   \n") == nil)
    }

    @Test("A sibling editor's helper is not mistaken for Antigravity's")
    func rejectsOtherProducts() {
        // Same executable name, same flags, different product: its quota is not Antigravity's.
        let other = "700 /Applications/Other.app/Contents/Resources/bin/language_server "
            + "--csrf_token abc123 --app_data_dir windsurf"
        #expect(AntigravityLocalServer.instance(inProcessTable: other) == nil)
    }

    @Test("A different executable carrying the same flags is not a match")
    func rejectsOtherExecutables() {
        let impostor = "700 /tmp/language_server_helper --csrf_token abc123 --app_data_dir antigravity"
        #expect(AntigravityLocalServer.instance(inProcessTable: impostor) == nil)
        let noPath = "700 language_server --csrf_token abc123 --app_data_dir antigravity"
        #expect(AntigravityLocalServer.instance(inProcessTable: noPath) == nil)
    }

    @Test("A helper with no usable token is skipped rather than half-used")
    func rejectsMissingToken() {
        let base = "700 /Applications/Antigravity.app/Contents/Resources/bin/language_server"
        // Flag absent entirely
        #expect(AntigravityLocalServer.instance(inProcessTable: "\(base) --app_data_dir antigravity") == nil)
        // Flag present but last on the line, so there is no value after it
        #expect(
            AntigravityLocalServer.instance(
                inProcessTable: "\(base) --app_data_dir antigravity --csrf_token"
            ) == nil
        )
    }

    @Test("Malformed leading fields are skipped, not parsed as a pid")
    func rejectsBadPID() {
        let suffix = "/Applications/Antigravity.app/Contents/Resources/bin/language_server "
            + "--csrf_token abc123 --app_data_dir antigravity"
        #expect(AntigravityLocalServer.instance(inProcessTable: "notapid \(suffix)") == nil)
        #expect(AntigravityLocalServer.instance(inProcessTable: "0 \(suffix)") == nil)
        #expect(AntigravityLocalServer.instance(inProcessTable: "-5 \(suffix)") == nil)
    }
}

// MARK: - Token validation

@Suite("AntigravityLocalServer.isUsableToken")
struct AntigravityTokenTests {

    @Test("The token the helper is launched with is accepted")
    func acceptsRealToken() {
        #expect(AntigravityLocalServer.isUsableToken("8e53559e-3cfa-4040-bfa9-003ac3e5701c"))
        #expect(AntigravityLocalServer.isUsableToken("abc123"))
        #expect(AntigravityLocalServer.isUsableToken("a-b_c.d~e"))
    }

    @Test("Anything that could forge a header is refused")
    func rejectsHeaderInjection() {
        #expect(!AntigravityLocalServer.isUsableToken("abc\r\nX-Evil: 1"))
        #expect(!AntigravityLocalServer.isUsableToken("abc\nX-Evil: 1"))
        #expect(!AntigravityLocalServer.isUsableToken("abc def"))
        #expect(!AntigravityLocalServer.isUsableToken("abc\t"))
        #expect(!AntigravityLocalServer.isUsableToken("abc\u{0}"))
        #expect(!AntigravityLocalServer.isUsableToken("abc:def"))
    }

    @Test("Empty and oversized tokens are refused")
    func rejectsSizes() {
        #expect(!AntigravityLocalServer.isUsableToken(""))
        #expect(AntigravityLocalServer.isUsableToken(String(repeating: "a", count: 256)))
        #expect(!AntigravityLocalServer.isUsableToken(String(repeating: "a", count: 257)))
    }
}

// MARK: - Socket table

@Suite("AntigravityLocalServer.loopbackPorts")
struct AntigravityPortTests {

    @Test("Both listening ports are returned, in the order reported")
    func readsPorts() {
        #expect(AntigravityLocalServer.loopbackPorts(inSocketTable: socketTable) == [52579, 52580])
    }

    @Test("No sockets means no ports")
    func noPorts() {
        #expect(AntigravityLocalServer.loopbackPorts(inSocketTable: "").isEmpty)
        let headerOnly = "COMMAND     PID     USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME"
        #expect(AntigravityLocalServer.loopbackPorts(inSocketTable: headerOnly).isEmpty)
    }

    @Test("Sockets bound anywhere but loopback are ignored")
    func ignoresNonLoopback() {
        let table = """
        language_ 26107 me 7u IPv4 0x1 0t0 TCP *:8080 (LISTEN)
        language_ 26107 me 8u IPv4 0x2 0t0 TCP 192.168.1.4:9000 (LISTEN)
        language_ 26107 me 9u IPv6 0x3 0t0 TCP [::1]:9100 (LISTEN)
        language_ 26107 me 10u IPv4 0x4 0t0 TCP 127.0.0.1:52580 (LISTEN)
        """
        #expect(AntigravityLocalServer.loopbackPorts(inSocketTable: table) == [52580])
    }

    @Test("Unparseable and out-of-range ports are dropped, and duplicates collapse")
    func rejectsBadPorts() {
        let table = """
        line 127.0.0.1:notaport (LISTEN)
        line 127.0.0.1: (LISTEN)
        line 127.0.0.1:0 (LISTEN)
        line 127.0.0.1:65536 (LISTEN)
        line 127.0.0.1:-1 (LISTEN)
        line 127.0.0.1:52580 (LISTEN)
        line 127.0.0.1:52580 (LISTEN)
        """
        #expect(AntigravityLocalServer.loopbackPorts(inSocketTable: table) == [52580])
    }
}
