import Foundation

/// Removes only the tracking parameters explicitly supported by Fluxa.
package enum URLCleaner {
    private static let genericTrackingParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "gclsrc", "dclid", "msclkid",
        "igshid", "mc_eid", "mc_cid",
        "_hsenc", "_hsmi",
        "ref_src", "ref_url",
    ]

    private static let youtubeHosts: Set<String> = [
        "youtube.com", "youtu.be", "music.youtube.com",
    ]

    private static let xHosts: Set<String> = ["x.com", "twitter.com"]

    /// Returns a cleaned URL, or nil if `url` needed no changes.
    package static func cleaned(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              let host = components.host,
              !host.isEmpty
        else {
            return nil
        }

        var didRemoveParameter = remove(genericTrackingParameters, from: &components)
        let normalizedHost = normalizedHost(host)

        if normalizedHost.hasPrefix("amazon."), let asin = amazonASIN(in: components.path) {
            var cleaned = URLComponents()
            cleaned.scheme = "https"
            cleaned.host = host
            cleaned.path = "/dp/\(asin)"
            guard let cleanedURL = cleaned.url, cleanedURL != url else { return nil }
            return cleanedURL
        }

        if youtubeHosts.contains(normalizedHost) {
            didRemoveParameter = remove(["si"], from: &components) || didRemoveParameter
        } else if xHosts.contains(normalizedHost) {
            didRemoveParameter = remove(["ref_src", "ref_url", "s", "t"], from: &components)
                || didRemoveParameter
        }

        guard didRemoveParameter else { return nil }
        return components.url
    }

    private static func remove(_ names: Set<String>, from components: inout URLComponents) -> Bool {
        guard let queryItems = components.queryItems else { return false }

        let remaining = queryItems.filter { !names.contains($0.name) }
        guard remaining.count != queryItems.count else { return false }

        components.queryItems = remaining.isEmpty ? nil : remaining
        return true
    }

    private static func normalizedHost(_ host: String) -> String {
        let lowercase = host.lowercased()
        return lowercase.hasPrefix("www.") ? String(lowercase.dropFirst(4)) : lowercase
    }

    private static func amazonASIN(in path: String) -> String? {
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)

        for index in segments.indices {
            if segments[index] == "dp", index + 1 < segments.endIndex {
                return String(segments[index + 1])
            }

            if segments[index] == "gp",
               index + 2 < segments.endIndex,
               segments[index + 1] == "product"
            {
                return String(segments[index + 2])
            }
        }

        return nil
    }
}
