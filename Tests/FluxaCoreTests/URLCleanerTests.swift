import Foundation
import Testing
@testable import FluxaCore

@Suite("URLCleaner")
struct URLCleanerTests {
    private let genericTrackingParameters = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "gclsrc", "dclid", "msclkid",
        "igshid", "mc_eid", "mc_cid",
        "_hsenc", "_hsmi",
        "ref_src", "ref_url",
    ]

    @Test("Each generic tracking parameter strips in isolation")
    func stripsEachGenericParameter() throws {
        for name in genericTrackingParameters {
            let input = try #require(URL(string: "https://example.com/path?\(name)=tracker"))
            let cleaned = try #require(URLCleaner.cleaned(input))

            #expect(cleaned.absoluteString == "https://example.com/path")
        }
    }

    @Test("Combined tracking parameters strip while unlisted parameters remain")
    func stripsCombinedGenericParameters() throws {
        let input = try #require(URL(
            string: "https://example.com/path?id=42&utm_source=a&fbclid=b&_hsmi=c"
        ))

        #expect(URLCleaner.cleaned(input)?.absoluteString == "https://example.com/path?id=42")
    }

    @Test("Generic parameter matching is exact and case-sensitive")
    func genericMatchingIsExactAndCaseSensitive() throws {
        let containingName = try #require(URL(string: "https://example.com/?not_utm_x=keep"))
        let uppercaseName = try #require(URL(string: "https://example.com/?UTM_SOURCE=keep"))

        #expect(URLCleaner.cleaned(containingName) == nil)
        #expect(URLCleaner.cleaned(uppercaseName) == nil)
    }

    @Test("YouTube strips si while preserving playback and playlist parameters")
    func appliesYouTubeRules() throws {
        let fixtures = [
            (
                "https://youtube.com/watch?v=video&si=share&t=42&list=playlist",
                "https://youtube.com/watch?v=video&t=42&list=playlist"
            ),
            (
                "https://www.youtube.com/watch?v=video&si=share&t=42&list=playlist",
                "https://www.youtube.com/watch?v=video&t=42&list=playlist"
            ),
            (
                "https://youtu.be/video?si=share&t=42&list=playlist",
                "https://youtu.be/video?t=42&list=playlist"
            ),
            (
                "https://music.youtube.com/watch?v=video&si=share&t=42&list=playlist",
                "https://music.youtube.com/watch?v=video&t=42&list=playlist"
            ),
        ]

        for (inputString, expected) in fixtures {
            let input = try #require(URL(string: inputString))
            #expect(URLCleaner.cleaned(input)?.absoluteString == expected)
        }
    }

    @Test("X and Twitter strip their host-specific share parameters")
    func appliesXRules() throws {
        for host in ["x.com", "www.x.com", "twitter.com", "www.twitter.com"] {
            let input = try #require(URL(
                string: "https://\(host)/user/status/1?id=keep&t=share&s=20&ref_src=twsrc&ref_url=source"
            ))

            #expect(URLCleaner.cleaned(input)?.absoluteString == "https://\(host)/user/status/1?id=keep")
        }
    }

    @Test("t remains untouched outside X and Twitter")
    func preservesTOnOtherHosts() throws {
        let input = try #require(URL(string: "https://example.com/watch?t=42"))
        #expect(URLCleaner.cleaned(input) == nil)
    }

    @Test("Amazon product paths collapse to canonical dp URLs")
    func canonicalizesAmazonProductPaths() throws {
        let fixtures = [
            (
                "http://www.amazon.com/Product-Name/dp/B0ABC12345/ref=share?tag=affiliate&utm_source=mail",
                "https://www.amazon.com/dp/B0ABC12345"
            ),
            (
                "https://amazon.co.uk/gp/product/B0XYZ98765?tag=affiliate&gclid=tracking",
                "https://amazon.co.uk/dp/B0XYZ98765"
            ),
        ]

        for (inputString, expected) in fixtures {
            let input = try #require(URL(string: inputString))
            #expect(URLCleaner.cleaned(input)?.absoluteString == expected)
        }
    }

    @Test("Non-product Amazon URLs receive only generic cleaning")
    func preservesNonProductAmazonParameters() throws {
        let input = try #require(URL(
            string: "https://www.amazon.com/s?k=keyboard&tag=affiliate&utm_source=mail"
        ))

        #expect(
            URLCleaner.cleaned(input)?.absoluteString
                == "https://www.amazon.com/s?k=keyboard&tag=affiliate"
        )
    }

    @Test("Already-clean URLs return nil")
    func cleanURLReturnsNil() throws {
        let input = try #require(URL(string: "https://example.com/path?id=42"))
        let canonicalAmazon = try #require(URL(string: "https://amazon.com/dp/B0ABC12345"))

        #expect(URLCleaner.cleaned(input) == nil)
        #expect(URLCleaner.cleaned(canonicalAmazon) == nil)
    }

    @Test("Removing the only parameter leaves no question mark")
    func removesTrailingQuestionMark() throws {
        let input = try #require(URL(string: "https://example.com/path?gclid=tracking"))
        #expect(URLCleaner.cleaned(input)?.absoluteString == "https://example.com/path")
    }

    @Test("Malformed and non-URL strings do not clean")
    func malformedInputsReturnNil() {
        for input in [
            "",
            "not-a-url",
            "not-a-url?utm_source=tracking",
            "this is not a URL",
            "://missing-scheme",
            "file:///Users/username/file.txt?utm_source=tracker",
            "data:text/plain;charset=utf-8,hello?utm_source=tracker",
        ] {
            let cleaned = URL(string: input).flatMap { URLCleaner.cleaned($0) }
            #expect(cleaned == nil)
        }
    }

    @Test("URL fragments, ports, and percent encoding are preserved during cleaning")
    func preservesFragmentsPortsAndEncoding() throws {
        let fragmentURL = try #require(URL(
            string: "https://example.com/docs/intro?utm_source=newsletter#getting-started"
        ))
        #expect(
            URLCleaner.cleaned(fragmentURL)?.absoluteString
                == "https://example.com/docs/intro#getting-started"
        )

        let portURL = try #require(URL(
            string: "https://localhost:8443/api/v1/resource?id=123&fbclid=abc"
        ))
        #expect(
            URLCleaner.cleaned(portURL)?.absoluteString
                == "https://localhost:8443/api/v1/resource?id=123"
        )

        let encodedURL = try #require(URL(
            string: "https://example.com/search?q=Swift%206%20concurrency&utm_medium=cpc&lang=it"
        ))
        #expect(
            URLCleaner.cleaned(encodedURL)?.absoluteString
                == "https://example.com/search?q=Swift%206%20concurrency&lang=it"
        )
    }

    @Test("International Amazon stores and case variations normalize correctly")
    func internationalAmazonStores() throws {
        let stores = [
            "amazon.de", "amazon.it", "amazon.co.jp", "amazon.fr", "amazon.es", "amazon.com.au"
        ]
        for domain in stores {
            let dpURL = try #require(URL(
                string: "https://www.\(domain)/some-title/dp/B08N5WRWNW?ref_=ast_sto_dp&th=1"
            ))
            #expect(
                URLCleaner.cleaned(dpURL)?.absoluteString
                    == "https://www.\(domain)/dp/B08N5WRWNW"
            )

            let gpURL = try #require(URL(
                string: "https://\(domain)/gp/product/B08N5WRWNW/?psc=1"
            ))
            #expect(
                URLCleaner.cleaned(gpURL)?.absoluteString
                    == "https://\(domain)/dp/B08N5WRWNW"
            )
        }
    }

    @Test("Fuzzing various query param combinations and empty values")
    func fuzzingQueryCombinations() throws {
        let emptyValURL = try #require(URL(
            string: "https://example.com/item?keep=1&utm_source=&gclid="
        ))
        #expect(
            URLCleaner.cleaned(emptyValURL)?.absoluteString
                == "https://example.com/item?keep=1"
        )

        let multipleDuplicates = try #require(URL(
            string: "https://example.com/item?tag=swift&utm_source=a&tag=macos&utm_source=b"
        ))
        #expect(
            URLCleaner.cleaned(multipleDuplicates)?.absoluteString
                == "https://example.com/item?tag=swift&tag=macos"
        )
    }

    @Test("Benchmark URL cleaning latency across multiple samples")
    func benchmarkURLCleaning() throws {
        let sampleURLs = [
            "https://youtube.com/watch?v=dQw4w9WgXcQ&si=tracking123&t=42&list=PL123",
            "https://www.amazon.com/Apple-MacBook-14-inch-Memory-Storage/dp/B0CX23V25C?ref=sr_1_1&tag=deals-20&utm_source=feed",
            "https://x.com/swiftlang/status/1800000000000000000?s=20&t=shareToken&ref_src=twsrc",
            "https://example.com/blog/article?utm_source=twitter&utm_medium=social&utm_campaign=launch&utm_content=v1&utm_term=macos&fbclid=abc123xyz&gclid=def456uvw&mc_eid=789",
            "https://clean-example.com/path/to/page?id=42&view=grid",
        ].compactMap { URL(string: $0) }

        let iterations = 10_000
        let start = DispatchTime.now().uptimeNanoseconds

        for _ in 0..<iterations {
            for url in sampleURLs {
                _ = URLCleaner.cleaned(url)
            }
        }

        let end = DispatchTime.now().uptimeNanoseconds
        let totalTimeNs = end - start
        let timePerOpNs = Double(totalTimeNs) / Double(iterations * sampleURLs.count)
        let timePerOpUs = timePerOpNs / 1000.0

        // Sanity bound: average cleaning per URL must stay well under 100 microseconds (typically < 3 µs)
        #expect(timePerOpUs < 100.0)
    }
}


