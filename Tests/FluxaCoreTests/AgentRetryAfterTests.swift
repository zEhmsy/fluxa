import Foundation
import Testing
@testable import FluxaCore

@Suite("AgentRetryAfter — delta seconds")
struct AgentRetryAfterSecondsTests {

    @Test("A plain second count is taken as-is")
    func plainSeconds() {
        #expect(AgentRetryAfter.seconds(from: "60") == 60)
        #expect(AgentRetryAfter.seconds(from: "  90  ") == 90)
        #expect(AgentRetryAfter.seconds(from: "0") == 0)
    }

    @Test("A negative wait means retry now, not an unreadable header")
    func negativeSeconds() {
        #expect(AgentRetryAfter.seconds(from: "-30") == 0)
    }

    @Test("An absurd wait is capped rather than obeyed")
    func cappedSeconds() {
        #expect(AgentRetryAfter.seconds(from: "999999") == AgentRetryAfter.maximumWait)
    }

    @Test("Nothing to read yields nil so the caller applies its own default")
    func unreadable() {
        #expect(AgentRetryAfter.seconds(from: nil) == nil)
        #expect(AgentRetryAfter.seconds(from: "") == nil)
        #expect(AgentRetryAfter.seconds(from: "   ") == nil)
        #expect(AgentRetryAfter.seconds(from: "soon") == nil)
        #expect(AgentRetryAfter.seconds(from: "nan") == nil)
        #expect(AgentRetryAfter.seconds(from: "inf") == nil)
    }
}

@Suite("AgentRetryAfter — HTTP-date")
struct AgentRetryAfterDateTests {

    /// 2026-09-05T12:00:00Z, the reference point every case below is measured from.
    private let now = Date(timeIntervalSince1970: 1_788_609_600)

    @Test("An HTTP-date becomes the distance from now")
    func futureDate() throws {
        let seconds = try #require(
            AgentRetryAfter.seconds(from: "Sat, 05 Sep 2026 12:02:00 GMT", now: now)
        )
        #expect(seconds == 120)
    }

    @Test("A date already past means retry now")
    func pastDate() {
        #expect(AgentRetryAfter.seconds(from: "Sat, 05 Sep 2026 11:00:00 GMT", now: now) == 0)
    }

    @Test("A far-future date is capped like a long delta")
    func farFutureDate() {
        #expect(
            AgentRetryAfter.seconds(from: "Sun, 06 Sep 2026 12:00:00 GMT", now: now)
                == AgentRetryAfter.maximumWait
        )
    }

    @Test("A malformed date is not guessed at")
    func malformedDate() {
        #expect(AgentRetryAfter.seconds(from: "Sat, 05 Sep 2026", now: now) == nil)
        #expect(AgentRetryAfter.seconds(from: "2026-09-05T12:02:00Z", now: now) == nil)
    }
}
