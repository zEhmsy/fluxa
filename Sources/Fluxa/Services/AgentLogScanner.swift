import Foundation

// MARK: - AgentLogScanner

/// Builds each agent's daily token history by reading the session logs the agents write themselves
/// (`~/.claude/projects/**/*.jsonl`, `~/.codex/sessions/**/*.jsonl`).
///
/// This is where the usage charts get their data. The quota endpoints only report a current
/// percentage, so a chart fed from live polling would start empty and stay thin for days — while
/// the logs already hold weeks of exact per-turn token counts.
///
/// The aggregation was verified against the same days OpenUsage reports: every past day matches to
/// the token for Claude, and 8 of 9 for Codex (see `scanCodexFile` for the one known gap).
///
/// An `actor` because it owns a mutable on-disk cache and does all its work off the main thread.
actor AgentLogScanner {

    /// Daily token totals per agent: providerID → "yyyy-MM-dd" (local) → tokens.
    typealias DailyTotals = [String: [String: Int]]

    // MARK: - Cache

    /// One scanned file. Logs are append-only, so a file whose size and modification date are
    /// unchanged cannot have new usage in it — its totals are reused without reading a byte. Only
    /// the sessions being written right now are ever re-read.
    private struct CachedFile: Codable {
        var size: Int64
        var modified: Date
        var byDay: [String: Int]
    }

    private var cache: [String: CachedFile] = [:]
    private var cacheLoaded = false

    private let cacheURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("Fluxa", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("log-scan-cache.json")
    }()

    // MARK: - Public API

    /// Scans both agents' logs and returns their daily token totals.
    func scan() -> DailyTotals {
        loadCacheIfNeeded()

        var totals: DailyTotals = [:]
        totals["claude"] = scanFiles(
            at: logFiles(in: "~/.claude/projects", extension: "jsonl"),
            marker: #""usage""#,
            parse: Self.scanClaudeFile
        )
        totals["codex"] = scanFiles(
            at: logFiles(in: "~/.codex/sessions", extension: "jsonl"),
            marker: #""token_count""#,
            parse: Self.scanCodexFile
        )
        saveCache()
        return totals
    }

    // MARK: - Scanning

    private func scanFiles(
        at urls: [URL],
        marker: String,
        parse: (Data) -> [String: Int]
    ) -> [String: Int] {
        var totals: [String: Int] = [:]
        var liveKeys: Set<String> = []

        for url in urls {
            let key = url.path
            liveKeys.insert(key)

            let attributes = try? FileManager.default.attributesOfItem(atPath: key)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let modified = attributes?[.modificationDate] as? Date ?? .distantPast

            if let cached = cache[key], cached.size == size, cached.modified == modified {
                merge(cached.byDay, into: &totals)
                continue
            }

            // A whole-file re-read rather than an offset seek: it only happens for files that
            // actually changed, and it keeps per-file de-duplication trivially correct (verified
            // to give the same totals as de-duplicating across every file at once).
            autoreleasepool {
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                      data.range(of: Data(marker.utf8)) != nil else {
                    cache[key] = CachedFile(size: size, modified: modified, byDay: [:])
                    return
                }
                let byDay = parse(data)
                cache[key] = CachedFile(size: size, modified: modified, byDay: byDay)
                merge(byDay, into: &totals)
            }
        }

        // Drop entries for logs that have since been deleted or rotated away.
        cache = cache.filter { liveKeys.contains($0.key) || !$0.key.hasPrefix("/Users") }
        return totals
    }

    /// Claude writes one JSON object per line; assistant turns carry `message.usage`. The four token
    /// fields are summed because that's the figure the agents' own tooling reports. A repeated
    /// `message.id` is the same turn replayed into the log (resumed sessions, sidechains) and is
    /// counted once.
    private static func scanClaudeFile(_ data: Data) -> [String: Int] {
        var byDay: [String: Int] = [:]
        var seen: Set<String> = []

        forEachLine(in: data, containing: #""usage""#) { object in
            guard let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let timestamp = object["timestamp"] as? String,
                  let day = localDay(fromISO: timestamp)
            else { return }

            if let id = (message["id"] as? String) ?? (object["requestId"] as? String) {
                guard seen.insert(id).inserted else { return }
            }

            let tokens = ["input_tokens", "output_tokens",
                          "cache_creation_input_tokens", "cache_read_input_tokens"]
                .reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
            byDay[day, default: 0] += tokens
        }
        return byDay
    }

    /// Codex emits a `token_count` event per turn, carrying both the turn's own usage
    /// (`last_token_usage`) and the session's running total. A line whose running total hasn't moved
    /// is a re-emitted stale snapshot, not new work, and is skipped — without that rule the totals
    /// run 0.2–1.8% high.
    ///
    /// Known gap: a child session replays its parent's history with rewritten timestamps, which
    /// OpenUsage additionally filters by watching for the first live `task_started`. That's not
    /// reproduced here; on the sampled history it accounted for 0.08% on one day out of nine.
    private static func scanCodexFile(_ data: Data) -> [String: Int] {
        var byDay: [String: Int] = [:]
        var previousTotal: Int?

        forEachLine(in: data, containing: #""token_count""#) { object in
            guard let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any]
            else { return }

            let runningTotal = (info["total_token_usage"] as? [String: Any])
                .flatMap { ($0["total_tokens"] as? NSNumber)?.intValue }
            if let runningTotal {
                if runningTotal == previousTotal { return }
                previousTotal = runningTotal
            }

            guard let last = info["last_token_usage"] as? [String: Any],
                  let tokens = (last["total_tokens"] as? NSNumber)?.intValue,
                  let timestamp = object["timestamp"] as? String,
                  let day = localDay(fromISO: timestamp)
            else { return }

            byDay[day, default: 0] += tokens
        }
        return byDay
    }

    // MARK: - Line parsing

    /// Splits `data` on newlines, keeps only lines containing `marker`, and hands each decoded
    /// object to `body`. The substring pre-filter is what keeps a 200MB scan tractable: most lines
    /// are prompts and tool output that never need to be parsed as JSON.
    private static func forEachLine(
        in data: Data,
        containing marker: String,
        _ body: ([String: Any]) -> Void
    ) {
        let markerBytes = Data(marker.utf8)
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            let slice = Data(line)
            guard slice.range(of: markerBytes) != nil,
                  let object = (try? JSONSerialization.jsonObject(with: slice)) as? [String: Any]
            else { continue }
            body(object)
        }
    }

    // MARK: - Dates

    /// Local calendar day for an ISO-8601 timestamp. Local, not UTC: bucketing by UTC moves an
    /// evening's work onto the next day for anyone east of Greenwich — which is exactly what made
    /// the first version disagree with the agents' own daily figures.
    private static func localDay(fromISO text: String) -> String? {
        guard let date = AgentDate.parse(text) else { return nil }
        return dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Files

    private func logFiles(in path: String, extension ext: String) -> [URL] {
        let root = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == ext }
    }

    private func merge(_ byDay: [String: Int], into totals: inout [String: Int]) {
        for (day, tokens) in byDay {
            totals[day, default: 0] += tokens
        }
    }

    // MARK: - Cache persistence

    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: CachedFile].self, from: data)
        else { return }
        cache = decoded
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
