// Adapted from CodexBar (MIT, © 2026 Peter Steinberger):
// Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner+Claude.swift
//
// Field shapes verified against real transcripts: assistant lines carry `message.model`,
// `message.id`, `message.usage.{input_tokens,output_tokens,cache_creation_input_tokens,
// cache_read_input_tokens}` and `usage.cache_creation.{ephemeral_5m,ephemeral_1h}_input_tokens`,
// plus a top-level `requestId` and `timestamp`.

import Foundation

enum ClaudeLogScanner {
    /// Only assistant lines carry usage, so skip everything else before parsing JSON.
    private static let assistantMarker = Array(#""type":"assistant""#.utf8)
    private static let usageMarker = Array(#""usage""#.utf8)

    static func projectRoots(env: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        if let configDir = env["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configDir.isEmpty {
            return [URL(fileURLWithPath: (configDir as NSString).expandingTildeInPath)
                .appendingPathComponent("projects", isDirectory: true)]
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent(".config/claude/projects", isDirectory: true),
        ]
    }

    /// Parses new bytes of every transcript into the cache. Returns the number of files touched.
    @discardableResult
    static func scan(
        cache: CostCache,
        overlay: PricingOverlay?,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Int {
        let files = LogFileScanner.jsonlFiles(under: self.projectRoots(env: env))
        try cache.pruneMissingFiles(provider: .claude, keeping: Set(files.map(\.path)))

        var touched = 0
        for url in files {
            let previous = cache.cursor(forPath: url.path)
            guard let plan = try? LogFileScanner.plan(for: url, previous: previous) else { continue }
            // Nothing appended since the last scan.
            if !plan.requiresFullReparse, plan.cursor.offset >= plan.cursor.size { continue }

            if plan.requiresFullReparse { try cache.forget(path: url.path) }

            try cache.beginTransaction()
            do {
                var parseError: Error?
                let newOffset = try LogFileScanner.readLines(of: url, from: plan.cursor.offset) { buffer in
                    guard parseError == nil else { return }
                    guard buffer.contains(ascii: Self.assistantMarker),
                          buffer.contains(ascii: Self.usageMarker) else { return }
                    do {
                        try Self.ingest(line: buffer, path: url.path, cache: cache, overlay: overlay)
                    } catch {
                        parseError = error
                    }
                }
                if let parseError { throw parseError }
                try cache.setCursor(
                    FileCursor(
                        inode: plan.cursor.inode,
                        size: plan.cursor.size,
                        offset: newOffset,
                        prefixDigest: plan.cursor.prefixDigest
                    ),
                    forPath: url.path,
                    provider: .claude
                )
                try cache.commit()
                touched += 1
            } catch {
                cache.rollback()
                Log.claude.warning("Skipped \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return touched
    }

    private static func ingest(
        line: UnsafeRawBufferPointer,
        path: String,
        cache: CostCache,
        overlay: PricingOverlay?
    ) throws {
        let data = Data(line)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "assistant",
              let message = root["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return }

        let rawModel = (message["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawModel.isEmpty, rawModel != "<synthetic>" else { return }
        // Normalize before storing so `claude-opus-5` and `claude-opus-5-20260101` aggregate as
        // one model rather than competing for the top-model slot.
        let model = CostPricing.normalizeClaudeModel(rawModel)

        // Anthropic reports input_tokens already net of both cache buckets, so unlike Codex
        // nothing has to be peeled out of it here.
        let cacheWrite = Self.int(usage["cache_creation_input_tokens"])
        let cacheCreation = usage["cache_creation"] as? [String: Any]
        let totals = TokenTotals(
            input: Self.int(usage["input_tokens"]),
            output: Self.int(usage["output_tokens"]),
            cacheWrite: cacheWrite,
            // The two TTLs are billed differently, and the 1h bucket dominates on long sessions.
            cacheWrite1h: min(Self.int(cacheCreation?["ephemeral_1h_input_tokens"]), cacheWrite),
            cacheRead: Self.int(usage["cache_read_input_tokens"])
        )
        guard totals.total > 0 else { return }

        guard let timestamp = root["timestamp"] as? String,
              let date = Self.parseTimestamp(timestamp) else { return }

        // The same assistant message is replayed into resumed and forked transcripts, so identity
        // comes from the message id paired with the request that produced it.
        let messageId = message["id"] as? String ?? ""
        let requestId = root["requestId"] as? String ?? ""
        let key: String
        if messageId.isEmpty, requestId.isEmpty {
            // Nothing stable to dedupe on; fall back to the line's own uuid.
            key = "uuid:\(root["uuid"] as? String ?? UUID().uuidString)"
        } else {
            key = "\(messageId)|\(requestId)"
        }

        // The long-context tier and price are properties of the individual request, so they have
        // to be decided here; deciding them from a day's aggregate would rewrite history.
        let longContext = CostPricing.isLongContext(
            totals: totals,
            model: model,
            provider: .claude,
            overlay: overlay
        )
        try cache.addClaudeMessage(
            key: key,
            path: path,
            day: DayKey.make(from: date),
            model: model,
            longContext: longContext,
            totals: totals,
            costUSD: CostPricing.cost(
                totals: totals,
                model: model,
                provider: .claude,
                longContext: longContext,
                overlay: overlay
            )
        )
    }

    private static func int(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    static func parseTimestamp(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}
