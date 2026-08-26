// Adapted from CodexBar (MIT, © 2026 Peter Steinberger):
// Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift
//
// Field shapes verified against real rollout files: `turn_context` announces the model for the
// turns that follow, and `event_msg` lines with `payload.type == "token_count"` carry
// `info.last_token_usage`, the delta for that turn. Summing those deltas reproduces the
// session's final `total_token_usage` exactly, which is what makes resuming mid-file safe.

import Foundation

enum CodexLogScanner {
    private static let tokenCountMarker = Array(#""token_count""#.utf8)
    private static let turnContextMarker = Array(#""turn_context""#.utf8)

    static func sessionRoots(env: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        let home: URL
        if let codexHome = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty {
            home = URL(fileURLWithPath: (codexHome as NSString).expandingTildeInPath)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }
        return [
            home.appendingPathComponent("sessions", isDirectory: true),
            home.appendingPathComponent("archived_sessions", isDirectory: true),
        ]
    }

    @discardableResult
    static func scan(
        cache: CostCache,
        overlay: PricingOverlay?,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Int {
        let files = LogFileScanner.jsonlFiles(under: self.sessionRoots(env: env))
        try cache.pruneMissingFiles(provider: .codex, keeping: Set(files.map(\.path)))

        var touched = 0
        for url in files {
            let previous = cache.cursor(forPath: url.path)
            guard let plan = try? LogFileScanner.plan(for: url, previous: previous) else { continue }
            if !plan.requiresFullReparse, plan.cursor.offset >= plan.cursor.size { continue }

            if plan.requiresFullReparse { try cache.forget(path: url.path) }

            // A resumed file starts after the turn_context that named the model, so recover the
            // model by rereading just the turn_context lines from the top.
            var currentModel = plan.cursor.offset > 0 ? Self.lastModel(in: url, before: plan.cursor.offset) : nil

            try cache.beginTransaction()
            do {
                var parseError: Error?
                let newOffset = try LogFileScanner.readLines(of: url, from: plan.cursor.offset) { buffer in
                    guard parseError == nil else { return }
                    let isTurnContext = buffer.contains(ascii: Self.turnContextMarker)
                    let isTokenCount = buffer.contains(ascii: Self.tokenCountMarker)
                    guard isTurnContext || isTokenCount else { return }
                    do {
                        try Self.ingest(
                            line: buffer,
                            path: url.path,
                            cache: cache,
                            overlay: overlay,
                            currentModel: &currentModel
                        )
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
                    provider: .codex
                )
                try cache.commit()
                touched += 1
            } catch {
                cache.rollback()
                Log.codex.warning("Skipped \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return touched
    }

    private static func ingest(
        line: UnsafeRawBufferPointer,
        path: String,
        cache: CostCache,
        overlay: PricingOverlay?,
        currentModel: inout String?
    ) throws {
        let data = Data(line)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if root["type"] as? String == "turn_context" {
            if let payload = root["payload"] as? [String: Any],
               let model = (payload["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !model.isEmpty {
                // Normalize on the way in so dated aliases aggregate as one model.
                currentModel = CostPricing.normalizeCodexModel(model)
            }
            return
        }

        guard root["type"] as? String == "event_msg",
              let payload = root["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any] else { return }

        let rawInput = Self.int(usage["input_tokens"])
        let cachedInput = Self.int(usage["cached_input_tokens"])
        let totals = TokenTotals(
            // Codex reports cached tokens as a subset of input_tokens, so split them apart to
            // price the cheap and the full-rate halves separately.
            input: max(0, rawInput - cachedInput),
            output: Self.int(usage["output_tokens"]),
            cacheWrite: Self.int(usage["cache_write_input_tokens"]),
            cacheRead: cachedInput
        )
        guard totals.total > 0 else { return }

        guard let timestamp = root["timestamp"] as? String,
              let date = ClaudeLogScanner.parseTimestamp(timestamp) else { return }

        // Older rollouts predate turn_context; count their tokens but leave them unpriced.
        let model = currentModel ?? CostPricing.unknownModel
        // The long-context tier and price belong to the individual turn, not to the day's total.
        let longContext = CostPricing.isLongContext(
            totals: totals,
            model: model,
            provider: .codex,
            overlay: overlay
        )
        try cache.addCodexTokens(
            path: path,
            day: DayKey.make(from: date),
            model: model,
            longContext: longContext,
            totals: totals,
            costUSD: CostPricing.cost(
                totals: totals,
                model: model,
                provider: .codex,
                longContext: longContext,
                overlay: overlay
            )
        )
    }

    /// Scans only the turn_context lines up to `offset` to recover the model in effect there.
    private static func lastModel(in url: URL, before offset: Int64) -> String? {
        var model: String?
        _ = try? LogFileScanner.readLines(of: url, from: 0) { buffer in
            guard buffer.contains(ascii: Self.turnContextMarker) else { return }
            guard let root = try? JSONSerialization.jsonObject(with: Data(buffer)) as? [String: Any],
                  root["type"] as? String == "turn_context",
                  let payload = root["payload"] as? [String: Any],
                  let value = (payload["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return }
            model = CostPricing.normalizeCodexModel(value)
        }
        return model
    }

    private static func int(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }
}
