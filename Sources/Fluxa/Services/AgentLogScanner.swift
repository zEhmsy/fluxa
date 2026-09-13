import FluxaCore
import Foundation
import SQLite3

// MARK: - AgentLogScanner

/// Builds each agent's daily token history from local session data: Claude/Codex JSONL logs and
/// Antigravity conversation databases.
///
/// This is where the usage charts get their data. The quota endpoints only report a current
/// percentage, so a chart fed from live polling would start empty and stay thin for days — while
/// the logs already hold weeks of exact per-turn token counts.
///
/// The aggregation was cross-checked against an independently computed set of daily totals for the
/// same days: every past day matches to the token for Claude, and 8 of 9 for Codex (see
/// `scanCodexFile` for the one known gap).
///
/// An `actor` because it owns a mutable on-disk cache and does all its work off the main thread.
actor AgentLogScanner {

    /// Daily token totals per agent: providerID → "yyyy-MM-dd" (local) → tokens.
    typealias DailyTotals = [String: [String: Int]]

    // MARK: - Cache

    /// One scanned file. JSONL logs use their size and modification date; Antigravity databases
    /// additionally include the WAL signature because their main file may remain unchanged during
    /// a live conversation.
    private struct CachedFile: Codable {
        var size: Int64
        var modified: Date
        var byDay: [String: Int]
        var companionSize: Int64? = nil
        var companionModified: Date? = nil
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

    /// Scans all agents' local usage data and returns their daily token totals.
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
        totals["antigravity"] = scanAntigravityDatabases()
        cache = cache.filter { FileManager.default.fileExists(atPath: $0.key) }

        saveCache()
        return totals
    }

    // MARK: - Scanning

    private func scanFiles(
        at urls: [URL],
        marker: String,
        parse: @Sendable (Data) -> [String: Int]
    ) -> [String: Int] {
        var totals: [String: Int] = [:]
        for url in urls {
            let key = url.path

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

        return totals
    }

    /// Claude writes one JSON object per line; assistant turns carry `message.usage`. The four token
    /// fields are summed because that's the figure the agents' own tooling reports. A repeated
    /// `message.id` is the same turn replayed into the log (resumed sessions, sidechains) and is
    /// counted once.
    @Sendable private static func scanClaudeFile(_ data: Data) -> [String: Int] {
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
    /// Known gap: a child session replays its parent's history with rewritten timestamps. Filtering
    /// those out needs a second rule — watch for the first live `task_started` — which is not
    /// reproduced here; on the sampled history it accounted for 0.08% on one day out of nine.
    @Sendable private static func scanCodexFile(_ data: Data) -> [String: Int] {
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

    // MARK: - Antigravity SQLite

    private static let maximumAntigravityDatabaseBytes: Int64 = 256 * 1_024 * 1_024

    private func scanAntigravityDatabases() -> [String: Int] {
        let databases = logFiles(in: "~/.gemini/antigravity/conversations", extension: "db")
        guard let scratchRoot = prepareAntigravityScratchDirectory() else { return [:] }

        var totals: [String: Int] = [:]
        for databaseURL in databases {
            autoreleasepool {
                let key = databaseURL.path
                let databaseSignature = fileSignature(at: databaseURL)
                let walSignature = fileSignature(at: URL(fileURLWithPath: key + "-wal"))

                if let cached = cache[key],
                   cached.size == databaseSignature.size,
                   cached.modified == databaseSignature.modified,
                   (cached.companionSize ?? 0) == walSignature.size,
                   (cached.companionModified ?? .distantPast) == walSignature.modified {
                    merge(cached.byDay, into: &totals)
                    return
                }

                let combinedSize = databaseSignature.size.addingReportingOverflow(walSignature.size)
                guard !combinedSize.overflow,
                      databaseSignature.size > 0,
                      combinedSize.partialValue <= Self.maximumAntigravityDatabaseBytes,
                      let copyURL = copyAntigravityDatabase(databaseURL, into: scratchRoot)
                else {
                    cache[key] = CachedFile(
                        size: databaseSignature.size,
                        modified: databaseSignature.modified,
                        byDay: [:],
                        companionSize: walSignature.size,
                        companionModified: walSignature.modified
                    )
                    return
                }

                let byDay = Self.readAntigravityDatabase(at: copyURL)
                cache[key] = CachedFile(
                    size: databaseSignature.size,
                    modified: databaseSignature.modified,
                    byDay: byDay,
                    companionSize: walSignature.size,
                    companionModified: walSignature.modified
                )
                merge(byDay, into: &totals)
            }
        }

        return totals
    }

    private func prepareAntigravityScratchDirectory() -> URL? {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base
            .appendingPathComponent("Fluxa", isDirectory: true)
            .appendingPathComponent("antigravity-scan", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            for item in try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) {
                try FileManager.default.removeItem(at: item)
            }
            return directory
        } catch {
            return nil
        }
    }

    private func copyAntigravityDatabase(_ source: URL, into scratchRoot: URL) -> URL? {
        let workDirectory = scratchRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let copyURL = workDirectory.appendingPathComponent("conversation.db")

        do {
            try FileManager.default.createDirectory(
                at: workDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.copyItem(at: source, to: copyURL)

            for suffix in ["-wal", "-shm"] {
                let companion = URL(fileURLWithPath: source.path + suffix)
                guard FileManager.default.fileExists(atPath: companion.path) else { continue }
                try FileManager.default.copyItem(
                    at: companion,
                    to: URL(fileURLWithPath: copyURL.path + suffix)
                )
            }

            return copyURL
        } catch {
            try? FileManager.default.removeItem(at: workDirectory)
            return nil
        }
    }

    private func fileSignature(at url: URL) -> (size: Int64, modified: Date) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (
            (attributes?[.size] as? NSNumber)?.int64Value ?? 0,
            attributes?[.modificationDate] as? Date ?? .distantPast
        )
    }

    private static func readAntigravityDatabase(at url: URL) -> [String: Int] {
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            if database != nil { sqlite3_close(database) }
            return [:]
        }
        defer { sqlite3_close(database) }

        let sql = "SELECT g.idx, g.data, s.metadata FROM gen_metadata g JOIN steps s ON s.idx = g.idx"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return [:] }
        defer { sqlite3_finalize(statement) }

        let earliestSaneTimestamp: UInt64 = 1_577_836_800
        let latestSaneTimestamp = UInt64(Date().addingTimeInterval(86_400).timeIntervalSince1970)
        var byDay: [String: Int] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let tokenData = sqliteData(from: statement, column: 1),
                  let timestampData = sqliteData(from: statement, column: 2),
                  let seconds = ProtobufScan.value(at: [1, 1], in: timestampData),
                  seconds >= earliestSaneTimestamp,
                  seconds <= latestSaneTimestamp,
                  let tokens = antigravityTokenTotal(in: tokenData)
            else { continue }

            let date = Date(timeIntervalSince1970: TimeInterval(seconds))
            let day = localDay(from: date)
            let addition = byDay[day, default: 0].addingReportingOverflow(tokens)
            guard !addition.overflow else { continue }
            byDay[day] = addition.partialValue
        }

        return byDay
    }

    private static func sqliteData(from statement: OpaquePointer, column: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private static func antigravityTokenTotal(in data: Data) -> Int? {
        var foundValue = false
        var total: UInt64 = 0

        for field in [1, 2, 3, 5] {
            guard let value = ProtobufScan.value(at: [1, 4, field], in: data) else { continue }
            foundValue = true
            let addition = total.addingReportingOverflow(value)
            guard !addition.overflow else { return nil }
            total = addition.partialValue
        }

        guard foundValue, total > 0, total <= UInt64(Int.max) else { return nil }
        return Int(total)
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
        return localDay(from: date)
    }

    private static func localDay(from date: Date) -> String {
        dayFormatter.string(from: date)
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
            let addition = totals[day, default: 0].addingReportingOverflow(tokens)
            guard !addition.overflow else { continue }
            totals[day] = addition.partialValue
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
