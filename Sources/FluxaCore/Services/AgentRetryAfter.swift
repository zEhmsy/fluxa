import Foundation

// MARK: - AgentRetryAfter

/// Reads an HTTP `Retry-After` header as a delay in seconds.
///
/// RFC 9110 allows two shapes — a count of seconds, or an HTTP-date — and the agent providers use
/// both. Accepting only one would turn a polite backoff into a loop that keeps hitting an endpoint
/// that just asked to be left alone.
///
/// Anything unparseable yields nil rather than a guess: the caller then applies its own default,
/// which is honest about not having understood the header.
package enum AgentRetryAfter {

    /// Longest wait worth honouring. A skewed clock or a stray header must not silence a meter until
    /// the app is relaunched, so a longer instruction is capped rather than obeyed.
    package static let maximumWait: TimeInterval = 60 * 60

    package static func seconds(from header: String?, now: Date = Date()) -> TimeInterval? {
        guard let text = header?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if let value = Double(text) {
            return clamped(value)
        }
        guard let date = httpDate(text) else { return nil }
        return clamped(date.timeIntervalSince(now))
    }

    /// A wait already in the past means "you may retry now", which is a valid answer and not the same
    /// as an unreadable header — hence 0 rather than nil.
    private static func clamped(_ seconds: Double) -> TimeInterval? {
        guard seconds.isFinite else { return nil }
        return min(max(0, seconds), maximumWait)
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private static func httpDate(_ text: String) -> Date? {
        httpDateFormatter.date(from: text)
    }
}
