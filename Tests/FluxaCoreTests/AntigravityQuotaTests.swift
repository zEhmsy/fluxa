import Foundation
import Testing
@testable import FluxaCore

// MARK: - Helpers

private func goKeyring(_ json: String) -> String {
    "go-keyring-base64:" + Data(json.utf8).base64EncodedString()
}

private func summary(_ json: String) -> Data { Data(json.utf8) }

// MARK: - Percent conversion

@Suite("AntigravityQuota.percentUsed")
struct AntigravityPercentUsedTests {

    @Test("Remaining fraction is inverted into percent used")
    func inversion() {
        // The endpoint reports what is LEFT; the strip shows what is SPENT. A full allowance must
        // read 0% used, never 100%.
        #expect(AntigravityQuota.percentUsed(remainingFraction: 1.0) == 0)
        #expect(AntigravityQuota.percentUsed(remainingFraction: 0.0) == 100)
        #expect(AntigravityQuota.percentUsed(remainingFraction: 0.25) == 75)
        #expect(AntigravityQuota.percentUsed(remainingFraction: 0.9) == 10)
    }

    @Test("Fractions round to the nearest percent")
    func rounding() {
        #expect(AntigravityQuota.percentUsed(remainingFraction: 0.005) == 100)
        #expect(AntigravityQuota.percentUsed(remainingFraction: 0.994) == 1)
        #expect(AntigravityQuota.percentUsed(remainingFraction: 0.996) == 0)
    }

    @Test("Out-of-range and non-finite fractions clamp instead of overflowing")
    func clamping() {
        #expect(AntigravityQuota.percentUsed(remainingFraction: 1.4) == 0)
        #expect(AntigravityQuota.percentUsed(remainingFraction: -3.0) == 100)
        #expect(AntigravityQuota.percentUsed(remainingFraction: .nan) == 0)
        #expect(AntigravityQuota.percentUsed(remainingFraction: .infinity) == 0)
        #expect(AntigravityQuota.percentUsed(remainingFraction: -.infinity) == 0)
    }

    @Test("Finite fractions far outside Int's range clamp rather than trapping")
    func extremeFinitePercentUsed() {
        // These are finite, so they pass the `isFinite` guard and reach the arithmetic. Converting
        // before clamping would trap here, turning a bad server value into a crash.
        #expect(AntigravityQuota.percentUsed(remainingFraction: -1e300) == 100)
        #expect(AntigravityQuota.percentUsed(remainingFraction: 1e300) == 0)
        #expect(AntigravityQuota.percentUsed(remainingFraction: .greatestFiniteMagnitude) == 0)
        #expect(AntigravityQuota.percentUsed(remainingFraction: -.greatestFiniteMagnitude) == 100)
    }
}

// MARK: - Quota summary parsing

@Suite("AntigravityQuota.metrics")
struct AntigravityMetricsTests {

    private static let fourPools = """
    {"groups":[{"buckets":[
      {"bucketId":"gemini-5h","remainingFraction":0.4,"resetTime":"2026-09-05T18:00:00Z"},
      {"bucketId":"gemini-weekly","remainingFraction":0.8},
      {"bucketId":"3p-5h","remainingFraction":0.0},
      {"bucketId":"3p-weekly","remainingFraction":1.0}
    ]}]}
    """

    @Test("All four pools map to ordered meters with inverted percentages")
    func fourPoolsMap() throws {
        let metrics = try #require(AntigravityQuota.metrics(fromSummary: summary(Self.fourPools)))
        #expect(metrics.count == 4)

        #expect(metrics.map(\.id) == [
            "antigravity.session", "antigravity.weekly",
            "antigravity.claude", "antigravity.claudeWeekly",
        ])
        #expect(metrics.map(\.label) == ["Session", "Weekly", "Claude", "Claude Weekly"])
        #expect(metrics.map(\.percentUsed) == [60, 20, 100, 0])
        #expect(metrics.allSatisfy { $0.providerID == "antigravity" })
        #expect(metrics.allSatisfy { $0.providerName == "Antigravity" })
    }

    @Test("Reset time is parsed when present and absent otherwise")
    func resetTimes() throws {
        let metrics = try #require(AntigravityQuota.metrics(fromSummary: summary(Self.fourPools)))
        let session = try #require(metrics.first { $0.id == "antigravity.session" })
        let weekly = try #require(metrics.first { $0.id == "antigravity.weekly" })

        #expect(session.resetsAt == ISO8601DateFormatter().date(from: "2026-09-05T18:00:00Z"))
        #expect(weekly.resetsAt == nil)
    }

    @Test("Fractional-second timestamps parse too")
    func fractionalTimestamp() throws {
        let json = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":0.5,"resetTime":"2026-09-05T18:00:00.250Z"}]}]}"#
        let metrics = try #require(AntigravityQuota.metrics(fromSummary: summary(json)))
        #expect(metrics.first?.resetsAt != nil)
    }

    @Test("Both the bare payload and the response envelope are accepted")
    func envelopeShapes() throws {
        let wrapped = #"{"response":{"groups":[{"buckets":[{"bucketId":"3p-weekly","remainingFraction":0.5}]}]}}"#
        let metrics = try #require(AntigravityQuota.metrics(fromSummary: summary(wrapped)))
        #expect(metrics.map(\.id) == ["antigravity.claudeWeekly"])
        #expect(metrics.first?.percentUsed == 50)
    }

    @Test("Buckets split across several groups are collected")
    func multipleGroups() throws {
        let json = """
        {"groups":[
          {"buckets":[{"bucketId":"gemini-5h","remainingFraction":0.5}]},
          {"buckets":[{"bucketId":"3p-5h","remainingFraction":0.5}]}
        ]}
        """
        let metrics = try #require(AntigravityQuota.metrics(fromSummary: summary(json)))
        #expect(metrics.map(\.id) == ["antigravity.session", "antigravity.claude"])
    }

    @Test("An unrecognized bucket id is ignored rather than joining a pool")
    func unknownBucket() throws {
        let json = """
        {"groups":[{"buckets":[
          {"bucketId":"gemini-image-5h","remainingFraction":0.1},
          {"bucketId":"gemini-5h","remainingFraction":0.5}
        ]}]}
        """
        let metrics = try #require(AntigravityQuota.metrics(fromSummary: summary(json)))
        #expect(metrics.map(\.id) == ["antigravity.session"])
        #expect(metrics.first?.percentUsed == 50)
    }

    @Test("A duplicate bucket id keeps the first occurrence")
    func duplicateBucket() throws {
        let json = """
        {"groups":[{"buckets":[
          {"bucketId":"gemini-5h","remainingFraction":0.5},
          {"bucketId":"gemini-5h","remainingFraction":0.1}
        ]}]}
        """
        let metrics = try #require(AntigravityQuota.metrics(fromSummary: summary(json)))
        #expect(metrics.count == 1)
        #expect(metrics.first?.percentUsed == 50)
    }

    @Test("A malformed bucket drops its own meter and leaves the rest standing")
    func malformedBucketIsolated() throws {
        let json = """
        {"groups":[{"buckets":[
          {"bucketId":"gemini-5h"},
          {"bucketId":"gemini-weekly","remainingFraction":"not a number"},
          {"remainingFraction":0.5},
          {"bucketId":"3p-5h","remainingFraction":0.25}
        ]}]}
        """
        let metrics = try #require(AntigravityQuota.metrics(fromSummary: summary(json)))
        #expect(metrics.map(\.id) == ["antigravity.claude"])
        #expect(metrics.first?.percentUsed == 75)
    }

    @Test("A numeric-string fraction is still read")
    func numericStringFraction() throws {
        let json = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":"0.25"}]}]}"#
        let metrics = try #require(AntigravityQuota.metrics(fromSummary: summary(json)))
        #expect(metrics.first?.percentUsed == 75)
    }

    @Test("A non-finite fraction drops its meter rather than inventing a number")
    func nonFiniteFraction() throws {
        let json = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":"nan"}]}]}"#
        let metrics = try #require(AntigravityQuota.metrics(fromSummary: summary(json)))
        #expect(metrics.isEmpty)
    }

    @Test("A body with no groups is not a summary")
    func missingGroups() {
        // Distinct from an empty success: the caller turns nil into "update Antigravity".
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"other":true}"#)) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"response":{}}"#)) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary("not json")) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: Data()) == nil)
    }

    @Test("A summary naming no known pool parses to an empty result, not a failure")
    func emptyButValid() throws {
        let metrics = try #require(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":[]}"#)))
        #expect(metrics.isEmpty)
    }
}

// MARK: - Credential parsing

@Suite("AntigravityQuota.credential")
struct AntigravityCredentialTests {

    @Test("A go-keyring wrapped blob with a nested token object is decoded")
    func nestedToken() throws {
        let raw = goKeyring("""
        {"token":{"access_token":"acc","refresh_token":"ref","expiry":"2026-09-05T18:00:00Z"}}
        """)
        let credential = try #require(AntigravityQuota.credential(fromKeychainValue: raw))
        #expect(credential.accessToken == "acc")
        #expect(credential.refreshToken == "ref")
        #expect(credential.expiresAt == ISO8601DateFormatter().date(from: "2026-09-05T18:00:00Z"))
    }

    @Test("Tokens at the root are read when there is no nested token object")
    func rootToken() throws {
        let raw = goKeyring(#"{"accessToken":"acc","refreshToken":"ref"}"#)
        let credential = try #require(AntigravityQuota.credential(fromKeychainValue: raw))
        #expect(credential.accessToken == "acc")
        #expect(credential.refreshToken == "ref")
        #expect(credential.expiresAt == nil)
    }

    @Test("Plain JSON without the go-keyring wrapper is accepted")
    func unwrappedJSON() throws {
        let credential = try #require(
            AntigravityQuota.credential(fromKeychainValue: #"{"token":{"access_token":"acc"}}"#)
        )
        #expect(credential.accessToken == "acc")
        #expect(credential.refreshToken == nil)
    }

    @Test("A refresh token alone is a valid credential")
    func refreshOnly() throws {
        let credential = try #require(
            AntigravityQuota.credential(fromKeychainValue: #"{"refresh_token":"ref"}"#)
        )
        #expect(credential.accessToken == nil)
        #expect(credential.refreshToken == "ref")
    }

    @Test("Bare string, bearer, and raw token values degrade to an access token")
    func bareValues() throws {
        #expect(AntigravityQuota.credential(fromKeychainValue: #""acc""#)?.accessToken == "acc")
        #expect(AntigravityQuota.credential(fromKeychainValue: "Bearer acc")?.accessToken == "acc")
        #expect(AntigravityQuota.credential(fromKeychainValue: "acc")?.accessToken == "acc")
    }

    @Test("Surrounding whitespace and a BOM are tolerated")
    func boundaryCharacters() throws {
        let raw = "\u{FEFF}  " + goKeyring(#"{"token":{"access_token":"acc"}}"#) + "  \n"
        #expect(AntigravityQuota.credential(fromKeychainValue: raw)?.accessToken == "acc")
    }

    @Test("Damaged structured material is rejected instead of being sent as a bearer token")
    func malformedRejected() {
        // Sending `{"token":` as a bearer value would turn "sign in again" into a confusing 401.
        #expect(AntigravityQuota.credential(fromKeychainValue: #"{"token":"#) == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "[broken") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "go-keyring-base64:!!!!") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "   ") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: #"{"unrelated":1}"#) == nil)
    }

    @Test("Epoch expiries are accepted in seconds and milliseconds")
    func epochExpiry() throws {
        let seconds = try #require(
            AntigravityQuota.credential(fromKeychainValue: #"{"access_token":"a","expiry":1788000000}"#)
        )
        let milliseconds = try #require(
            AntigravityQuota.credential(fromKeychainValue: #"{"access_token":"a","expiry":1788000000000}"#)
        )
        #expect(seconds.expiresAt == Date(timeIntervalSince1970: 1_788_000_000))
        #expect(milliseconds.expiresAt == Date(timeIntervalSince1970: 1_788_000_000))
    }
}

// MARK: - Access token usability

@Suite("AntigravityQuota.StoredCredential")
struct AntigravityStoredCredentialTests {

    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    private func credential(expiresIn seconds: TimeInterval?, token: String? = "acc") -> AntigravityQuota.StoredCredential {
        AntigravityQuota.StoredCredential(
            accessToken: token,
            refreshToken: "ref",
            expiresAt: seconds.map { now.addingTimeInterval($0) }
        )
    }

    @Test("A comfortably live token is usable and an expired one is not")
    func expiryBoundaries() {
        #expect(credential(expiresIn: 3600).hasUsableAccessToken(now: now))
        #expect(!credential(expiresIn: -1).hasUsableAccessToken(now: now))
    }

    @Test("A token inside the refresh buffer counts as already expired")
    func bufferWindow() {
        // Spending a request on a token about to expire earns a near-certain 401 and a second
        // round trip; refreshing first is cheaper.
        #expect(!credential(expiresIn: 30).hasUsableAccessToken(now: now))
        #expect(credential(expiresIn: 120).hasUsableAccessToken(now: now))
    }

    @Test("An unknown expiry is treated as usable, a missing token never is")
    func unknownExpiryAndMissingToken() {
        #expect(credential(expiresIn: nil).hasUsableAccessToken(now: now))
        #expect(!credential(expiresIn: 3600, token: nil).hasUsableAccessToken(now: now))
        #expect(!credential(expiresIn: nil, token: "").hasUsableAccessToken(now: now))
    }
}

// MARK: - Fuzzing

@Suite("AntigravityQuota.fuzzing")
struct AntigravityFuzzingTests {

    @Test("Fuzz percentUsed with various extreme and boundary inputs")
    func percentUsedFuzzing() {
        let extremeValues: [Double] = [
            -Double.greatestFiniteMagnitude,
            Double.greatestFiniteMagnitude,
            -1e300,
            1e300,
            -Double.leastNonzeroMagnitude,
            Double.leastNonzeroMagnitude,
            -Double.leastNormalMagnitude,
            Double.leastNormalMagnitude,
            0.0,
            -0.0,
            1.0,
            -1.0,
            0.5,
            0.005,
            0.995,
            0.0000001,
            0.9999999,
            -0.0000001,
            1.0000001,
            .nan,
            -.nan,
            .infinity,
            -.infinity,
        ]

        for val in extremeValues {
            let result = AntigravityQuota.percentUsed(remainingFraction: val)
            #expect(result >= 0 && result <= 100, "percentUsed for \(val) returned out-of-bounds \(result)")
        }
    }

    @Test("Fuzz credential parsing with malformed, wrapped, corrupted, and extreme inputs")
    func credentialFuzzing() {
        // Empty and whitespace
        #expect(AntigravityQuota.credential(fromKeychainValue: "") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "   \t\r\n   ") == nil)

        // BOM edge cases
        #expect(AntigravityQuota.credential(fromKeychainValue: "\u{FEFF}") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "\u{FEFF}   \n") == nil)
        let bomJSON = "\u{FEFF}{\"access_token\":\"tok\"}"
        #expect(AntigravityQuota.credential(fromKeychainValue: bomJSON)?.accessToken == "tok")

        // Truncated wrapper
        #expect(AntigravityQuota.credential(fromKeychainValue: "go-keyring-base64:") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "go-keyring-base64:   ") == nil)

        // Malformed base64
        #expect(AntigravityQuota.credential(fromKeychainValue: "go-keyring-base64:====") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "go-keyring-base64:not_valid_b64!!!") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "go-keyring-base64:abc") == nil)

        // Invalid UTF-8 in base64
        let invalidUtf8Data = Data([0xFF, 0xFE, 0xFD, 0xFC])
        let invalidUtf8Base64 = "go-keyring-base64:" + invalidUtf8Data.base64EncodedString()
        #expect(AntigravityQuota.credential(fromKeychainValue: invalidUtf8Base64) == nil)

        // Deeply nested JSON
        var deeplyNested = #"{"access_token":"deep"}"#
        for _ in 0..<50 {
            deeplyNested = "{\"token\":\(deeplyNested)}"
        }
        // Beyond the single level of `token` nesting, it must return nil safely without crashing
        #expect(AntigravityQuota.credential(fromKeychainValue: deeplyNested) == nil)

        // Huge blob (100 KB)
        let largePadding = String(repeating: "a", count: 100_000)
        let hugeBlob = #"{"access_token":""# + largePadding + #""}"#
        let hugeCred = AntigravityQuota.credential(fromKeychainValue: hugeBlob)
        #expect(hugeCred?.accessToken == largePadding)

        // Duplicate keys
        let duplicateKeys = #"{"access_token":"first","access_token":"second"}"#
        #expect(AntigravityQuota.credential(fromKeychainValue: duplicateKeys) != nil)

        // Wrong types for fields
        #expect(AntigravityQuota.credential(fromKeychainValue: #"{"token":{"access_token":123}}"#) == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: #"{"token":{"access_token":true}}"#) == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: #"{"token":{"access_token":[1,2]}}"#) == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: #"{"token":{"access_token":{"nested":"val"}}}"#) == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: #"{"token":{"access_token":null}}"#) == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: #"{"token":{"refresh_token":false}}"#) == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: #"{"token":{"refresh_token":999}}"#) == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: #"{"token":{"refresh_token":[1]}}"#) == nil)

        // Wrong type for expiry does not void the token
        let badExpiryCred = AntigravityQuota.credential(fromKeychainValue: #"{"token":{"access_token":"tok","expiry":"not-a-date"}}"#)
        #expect(badExpiryCred?.accessToken == "tok")
        #expect(badExpiryCred?.expiresAt == nil)

        let badExpiryArray = AntigravityQuota.credential(fromKeychainValue: #"{"token":{"access_token":"tok","expiry":["2026-09-05"]}}"#)
        #expect(badExpiryArray?.accessToken == "tok")
        #expect(badExpiryArray?.expiresAt == nil)

        // Bare primitives
        #expect(AntigravityQuota.credential(fromKeychainValue: "12345") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "-42.5") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "true") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "false") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "null") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "[1, 2, 3]") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "[]") == nil)

        // Malformed structured text (starting with { or [)
        #expect(AntigravityQuota.credential(fromKeychainValue: "{") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "{\"token\":") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "[broken") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "{}}") == nil)
        #expect(AntigravityQuota.credential(fromKeychainValue: "[}") == nil)
    }

    @Test("Fuzz metrics parsing with malformed and hostile payloads")
    func metricsFuzzing() {
        // Nil contract cases: undecodable or missing/non-array groups
        #expect(AntigravityQuota.metrics(fromSummary: Data()) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary("not json")) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary("{}")) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"other":true}"#)) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":null}"#)) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":true}"#)) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":42}"#)) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":"string"}"#)) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":{}}"#)) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":["not a dict"]}"#)) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"response":{"groups":null}}"#)) == nil)
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"response":"not a dict"}"#)) == nil)

        // Empty array contract cases: understood summary but no known pools
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":[]}"#)) == [])
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":[{}]}"#)) == [])
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":[{"buckets":[]}]}"#)) == [])
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":[{"buckets":null}]}"#)) == [])
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":[{"buckets":"not-array"}]}"#)) == [])
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":[{"buckets":[{"bucketId":"unknown"}]}]}"#)) == [])
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":[{"buckets":[{"bucketId":123}]}]}"#)) == [])
        #expect(AntigravityQuota.metrics(fromSummary: summary(#"{"groups":[{"buckets":[{"bucketId":null}]}]}"#)) == [])

        // remainingFraction variations
        let jsonNullFrac = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":null}]}]}"#
        #expect(AntigravityQuota.metrics(fromSummary: summary(jsonNullFrac))?.isEmpty == true)

        let jsonArrayFrac = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":[0.5]}]}]}"#
        #expect(AntigravityQuota.metrics(fromSummary: summary(jsonArrayFrac))?.isEmpty == true)

        let jsonDictFrac = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":{"val":0.5}}]}]}"#
        #expect(AntigravityQuota.metrics(fromSummary: summary(jsonDictFrac))?.isEmpty == true)

        let jsonEmptyStrFrac = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":""}]}]}"#
        #expect(AntigravityQuota.metrics(fromSummary: summary(jsonEmptyStrFrac))?.isEmpty == true)

        let jsonGarbageStrFrac = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":"garbage"}]}]}"#
        #expect(AntigravityQuota.metrics(fromSummary: summary(jsonGarbageStrFrac))?.isEmpty == true)

        // Extreme finite remainingFraction
        let jsonExtremeFrac = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":-1e300}]}]}"#
        let extremeMetric = AntigravityQuota.metrics(fromSummary: summary(jsonExtremeFrac))
        #expect(extremeMetric?.first?.percentUsed == 100)

        // An absurd resetTime used to build a Date beyond Int.max, which then trapped
        // Int(_: Double) inside resetNote() — a server value crashing the app from a tooltip. The
        // meter must survive; only its countdown is lost.
        let jsonExtremeReset = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":0.5,"resetTime":1e300}]}]}"#
        let extremeResetMetric = AntigravityQuota.metrics(fromSummary: summary(jsonExtremeReset))
        #expect(extremeResetMetric?.first?.percentUsed == 50)
        #expect(extremeResetMetric?.first?.resetsAt == nil)
        #expect(extremeResetMetric?.first?.resetNote() == nil)

        // resetTime variations
        let jsonNullReset = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":0.5,"resetTime":null}]}]}"#
        let nullResetMetric = AntigravityQuota.metrics(fromSummary: summary(jsonNullReset))
        #expect(nullResetMetric?.first?.percentUsed == 50)
        #expect(nullResetMetric?.first?.resetsAt == nil)

        let jsonInvalidReset = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":0.5,"resetTime":"not a date"}]}]}"#
        let invalidResetMetric = AntigravityQuota.metrics(fromSummary: summary(jsonInvalidReset))
        #expect(invalidResetMetric?.first?.percentUsed == 50)
        #expect(invalidResetMetric?.first?.resetsAt == nil)

        let jsonNumericReset = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":0.5,"resetTime":1788000000}]}]}"#
        let numericMetric = AntigravityQuota.metrics(fromSummary: summary(jsonNumericReset))
        #expect(numericMetric?.first?.resetsAt == Date(timeIntervalSince1970: 1_788_000_000))

        let jsonNumericMilliReset = #"{"groups":[{"buckets":[{"bucketId":"gemini-5h","remainingFraction":0.5,"resetTime":1788000000000}]}]}"#
        let numericMilliMetric = AntigravityQuota.metrics(fromSummary: summary(jsonNumericMilliReset))
        #expect(numericMilliMetric?.first?.resetsAt == Date(timeIntervalSince1970: 1_788_000_000))
    }
}

// MARK: - Reset note

/// `resetNote` is shared by every provider, and each one's parser can hand it a `Date` built from
/// an unbounded epoch number off the network. It is the last line before the arithmetic, so it has
/// to hold on its own rather than trusting its callers.
@Suite("AgentUsageMetric.resetNote")
struct AgentUsageResetNoteTests {

    private func metric(resetsAt: Date?) -> AgentUsageMetric {
        AgentUsageMetric(
            id: "antigravity.session",
            providerID: "antigravity",
            providerName: "Antigravity",
            label: "Session",
            percentUsed: 50,
            resetsAt: resetsAt
        )
    }

    @Test("Ordinary intervals render as before")
    func ordinaryIntervals() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        #expect(metric(resetsAt: now.addingTimeInterval(45 * 60)).resetNote(now: now) == "resets in 45m")
        #expect(metric(resetsAt: now.addingTimeInterval(2 * 3600 + 45 * 60)).resetNote(now: now) == "resets in 2h 45m")
        #expect(metric(resetsAt: now.addingTimeInterval(50 * 3600)).resetNote(now: now) == "resets in 2d 2h")
    }

    @Test("Unknown and past resets produce no note")
    func absentAndPast() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        #expect(metric(resetsAt: nil).resetNote(now: now) == nil)
        #expect(metric(resetsAt: now.addingTimeInterval(-60)).resetNote(now: now) == nil)
        #expect(metric(resetsAt: now).resetNote(now: now) == nil)
    }

    @Test("A reset date beyond Int's range clamps instead of trapping")
    func extremeResetDate() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        // Each of these would trap in `Int(_: Double)` if the interval reached it unclamped.
        for interval in [1e300, 1e30, Double(Int.max) * 2, .greatestFiniteMagnitude] as [Double] {
            let note = metric(resetsAt: now.addingTimeInterval(interval)).resetNote(now: now)
            #expect(note == "resets in 3650d 0h")
        }
    }

    @Test("A far-future but representable reset still clamps to the cap")
    func farFutureResetDate() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let elevenYears = 11 * 365 * 24 * 60 * 60.0
        #expect(metric(resetsAt: now.addingTimeInterval(elevenYears)).resetNote(now: now) == "resets in 3650d 0h")
    }
}

// MARK: - Benchmarks

@Suite("AntigravityQuota.benchmarks")
struct AntigravityBenchmarkTests {

    private static let sampleSummary = """
    {"groups":[{"buckets":[
      {"bucketId":"gemini-5h","remainingFraction":0.35,"resetTime":"2026-09-05T18:00:00Z"},
      {"bucketId":"gemini-weekly","remainingFraction":0.80,"resetTime":"2026-09-12T00:00:00Z"},
      {"bucketId":"3p-5h","remainingFraction":0.10,"resetTime":"2026-09-05T18:00:00Z"},
      {"bucketId":"3p-weekly","remainingFraction":0.95,"resetTime":"2026-09-12T00:00:00Z"}
    ]}]}
    """

    private static let sampleCredential = goKeyring("""
    {"token":{"access_token":"ya29.sample_access_token_fluxa_benchmarks","refresh_token":"1//sample_refresh_token","expiry":"2026-09-05T18:00:00Z"}}
    """)

    @Test("Benchmark AntigravityQuota.metrics parsing latency across 1,000 iterations")
    func benchmarkMetricsParsing() {
        let data = Data(Self.sampleSummary.utf8)
        let iterations = 1_000
        let start = DispatchTime.now().uptimeNanoseconds

        for _ in 0..<iterations {
            _ = AntigravityQuota.metrics(fromSummary: data)
        }

        let end = DispatchTime.now().uptimeNanoseconds
        let totalNs = end - start
        let perOpUs = Double(totalNs) / Double(iterations) / 1_000.0

        // JSON parsing + ISO8601 formatting across 4 buckets completes in under 1.5 ms per call
        #expect(perOpUs < 1500.0)
    }

    @Test("Benchmark AntigravityQuota.credential parsing latency across 1,000 iterations")
    func benchmarkCredentialParsing() {
        let raw = Self.sampleCredential
        let iterations = 1_000
        let start = DispatchTime.now().uptimeNanoseconds

        for _ in 0..<iterations {
            _ = AntigravityQuota.credential(fromKeychainValue: raw)
        }

        let end = DispatchTime.now().uptimeNanoseconds
        let totalNs = end - start
        let perOpUs = Double(totalNs) / Double(iterations) / 1_000.0

        // Base64 unwrap + JSON decode + ISO8601 format completes in under 1.0 ms per call
        #expect(perOpUs < 1000.0)
    }
}
