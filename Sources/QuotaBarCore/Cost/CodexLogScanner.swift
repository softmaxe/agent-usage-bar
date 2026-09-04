// Adapted from CodexBar (MIT, © 2026 Peter Steinberger):
// Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift
//
// Field shapes verified against real rollout files: `turn_context` announces the model for the
// turns that follow, and `event_msg` lines with `payload.type == "token_count"` carry
// `info.last_token_usage`, the delta for that turn. Summing those deltas reproduces the
// session's final `total_token_usage` exactly, which is what makes resuming mid-file safe.

import Foundation

enum CodexLogScanner {
    static func sessionRoots(env: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        let home = CodexHome.url(env: env)
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

            // A resumed file starts after the turn_context that named the model and after the
            // token_count that a re-emission would repeat, so replay the prefix to recover both.
            var state = plan.cursor.offset > 0
                ? Self.resumeState(in: url, before: plan.cursor.offset)
                : ResumeState()

            try cache.beginTransaction()
            do {
                var parseError: Error?
                let newOffset = try LogFileScanner.readLines(
                    of: url,
                    from: plan.cursor.offset,
                    upTo: plan.cursor.size
                ) { buffer in
                    guard parseError == nil else { return }
                    guard Self.isRelevant(buffer) else { return }
                    do {
                        try Self.ingest(
                            line: buffer,
                            path: url.path,
                            cache: cache,
                            overlay: overlay,
                            state: &state
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

    /// What a resumed scan has to know about the bytes it is skipping past.
    struct ResumeState {
        /// Model announced by the most recent turn_context.
        var model: String?
        /// Service tier applied to subsequent turns.
        var serviceTier: CostPricing.CodexServiceTier = .standard
        /// The most recent `total_token_usage`, which is how a re-emitted event is recognised.
        var lastTotalUsage: [String: Int]?
    }

    private static func ingest(
        line: UnsafeRawBufferPointer,
        path: String,
        cache: CostCache,
        overlay: PricingOverlay?,
        state: inout ResumeState
    ) throws {
        let data = Data(line)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if root["type"] as? String == "turn_context" {
            if let payload = root["payload"] as? [String: Any] {
                if let tier = payload["service_tier"] as? String {
                    state.serviceTier = Self.serviceTier(tier)
                }
                if let model = (payload["model"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
                    // Normalize on the way in so dated aliases aggregate as one model.
                    state.model = CostPricing.normalizeCodexModel(model)
                }
            }
            return
        }

        if root["type"] as? String == "event_msg",
           let payload = root["payload"] as? [String: Any],
           payload["type"] as? String == "thread_settings_applied" {
            let settings = payload["thread_settings"] as? [String: Any]
            state.serviceTier = Self.serviceTier(settings?["service_tier"] as? String)
            return
        }

        guard root["type"] as? String == "event_msg",
              let payload = root["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any] else { return }

        // Codex re-emits a token_count when the rate-limit block refreshes without a new turn.
        // Those events repeat the previous last_token_usage while the running total stands still,
        // so the running total is what tells a real turn from a replay.
        let runningTotal = Self.totals(info["total_token_usage"])
        defer { if let runningTotal { state.lastTotalUsage = runningTotal } }
        if let runningTotal, runningTotal == state.lastTotalUsage { return }

        // Codex reports input_tokens as the whole prompt, with the cached reads and the cache
        // writes both carved out of it. Peel them off in turn so each bucket is priced once.
        let rawInput = max(0, JSONNumber.int(usage["input_tokens"]))
        let cacheRead = min(max(0, JSONNumber.int(usage["cached_input_tokens"])), rawInput)
        let cacheWrite = min(max(0, JSONNumber.int(usage["cache_write_input_tokens"])), rawInput - cacheRead)
        let totals = TokenTotals(
            input: rawInput - cacheRead - cacheWrite,
            // reasoning_output_tokens is a subset of output_tokens, which is what OpenAI bills.
            output: JSONNumber.int(usage["output_tokens"]),
            cacheWrite: cacheWrite,
            cacheRead: cacheRead
        )
        guard totals.total > 0 else { return }

        guard let timestamp = root["timestamp"] as? String,
              let date = ISO8601.parse(timestamp) else { return }

        // Older rollouts predate turn_context; count their tokens but leave them unpriced.
        let model = state.model ?? CostPricing.unknownModel
        // The long-context tier and price belong to the individual turn, not to the day's total.
        let pricing = CostPricing.pricing(
            forNormalizedModel: model,
            provider: .codex,
            overlay: overlay,
            codexServiceTier: state.serviceTier
        )
        let longContext = CostPricing.isLongContext(totals: totals, pricing: pricing)
        try cache.addCodexTokens(
            path: path,
            day: DayKey.make(from: date),
            model: model,
            longContext: longContext,
            isFast: state.serviceTier.isFast,
            totals: totals,
            costUSD: pricing?.cost(for: totals, longContext: longContext)
        )
    }

    private static func isRelevant(_ buffer: UnsafeRawBufferPointer) -> Bool {
        switch JSONLogClassifier.topLevelType(in: buffer) {
        case .indeterminate:
            return true
        case .turnContext:
            return true
        case .eventMessage:
            switch JSONLogClassifier.payloadType(in: buffer) {
            case .indeterminate, .threadSettingsApplied, .tokenCount: return true
            default: return false
            }
        default:
            return false
        }
    }

    /// Replays the bytes before `offset` to recover the state a resumed scan would otherwise
    /// have lost. Bounded by `offset`: reading past it would pick up a model announced in the
    /// appended region and attribute the turns before it to the wrong model.
    private static func resumeState(in url: URL, before offset: Int64) -> ResumeState {
        var state = ResumeState()
        _ = try? LogFileScanner.readLines(of: url, from: 0, upTo: offset) { buffer in
            guard Self.isRelevant(buffer) else { return }
            guard let root = try? JSONSerialization.jsonObject(with: Data(buffer)) as? [String: Any],
                  let payload = root["payload"] as? [String: Any] else { return }

            if root["type"] as? String == "turn_context" {
                if let tier = payload["service_tier"] as? String {
                    state.serviceTier = Self.serviceTier(tier)
                }
                guard let value = (payload["model"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
                state.model = CostPricing.normalizeCodexModel(value)
                return
            }

            if root["type"] as? String == "event_msg",
               payload["type"] as? String == "thread_settings_applied" {
                let settings = payload["thread_settings"] as? [String: Any]
                state.serviceTier = Self.serviceTier(settings?["service_tier"] as? String)
                return
            }

            guard root["type"] as? String == "event_msg",
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let total = Self.totals(info["total_token_usage"]) else { return }
            state.lastTotalUsage = total
        }
        return state
    }

    private static func serviceTier(_ raw: String?) -> CostPricing.CodexServiceTier {
        CostPricing.CodexServiceTier.parse(raw)
    }

    /// The integer fields of a `*_token_usage` object, which is what makes two events comparable.
    private static func totals(_ value: Any?) -> [String: Int]? {
        guard let usage = value as? [String: Any] else { return nil }
        return usage.compactMapValues { ($0 as? NSNumber)?.intValue }
    }
}
