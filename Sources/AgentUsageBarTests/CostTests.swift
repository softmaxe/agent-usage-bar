import AgentUsageBarCore
import Combine
import Foundation

/// Cost-layer checks. The scan tests build synthetic transcripts in a temp directory and drive
/// the real scanner through `CostService`, with pricing pinned so nothing touches the network.
enum CostTests {
    static func run() async {
        Self.pricingLookup()
        Self.normalization()
        Self.longContextTiering()
        Self.overlayParsing()
        Self.catalogRefreshBackoff()
        await Self.scanning()
        await Self.pricingEditsApplyForward()
    }

    // MARK: - Pricing

    private static func pricingLookup() {
        // CodexBar's table predates these two; they are the reason the built-in table was extended.
        for model in ["claude-opus-5", "claude-sonnet-5"] {
            Harness.expect(
                CostPricing.pricing(for: model, provider: .claude) != nil,
                "\(model) must have a built-in price"
            )
        }

        // 1M input + 1M output on Opus 5 at $5/$25 per million.
        let cost = CostPricing.cost(
            totals: TokenTotals(input: 1_000_000, output: 1_000_000),
            model: "claude-opus-5",
            provider: .claude,
            longContext: false
        )
        Harness.expectEqual(cost, 30.0, "opus-5 cost for 1M in + 1M out")

        // Cache read is a tenth of input; cache write is 1.25x.
        let cacheCost = CostPricing.cost(
            totals: TokenTotals(cacheWrite: 1_000_000, cacheRead: 1_000_000),
            model: "claude-opus-5",
            provider: .claude,
            longContext: false
        )
        Harness.expectEqual(cacheCost, 6.75, "opus-5 cache cost for 1M write + 1M read")

        // An unknown model must return nil rather than silently costing zero.
        Harness.expect(
            CostPricing.cost(
                totals: TokenTotals(input: 1_000_000),
                model: "some-model-nobody-priced",
                provider: .claude,
                longContext: false
            ) == nil,
            "unknown models must not be priced"
        )
    }

    private static func normalization() {
        Harness.expectEqual(
            CostPricing.normalizeClaudeModel("claude-haiku-4-5-20251001"),
            "claude-haiku-4-5",
            "claude date suffix stripped"
        )
        Harness.expectEqual(
            CostPricing.normalizeClaudeModel("anthropic.claude-opus-4-6-v1:0"),
            "claude-opus-4-6",
            "bedrock prefix and version suffix stripped"
        )
        Harness.expectEqual(
            CostPricing.normalizeCodexModel("openai/gpt-5.1-2026-01-01"),
            "gpt-5.1",
            "codex vendor prefix and dated suffix stripped"
        )
        Harness.expectEqual(CostPricing.normalizeCodexModel("gpt-5.6"), "gpt-5.6-sol", "sol alias applied")
    }

    private static func longContextTiering() {
        // gpt-5.6-sol charges double above 270k tokens in one request.
        let below = TokenTotals(input: 100_000)
        let above = TokenTotals(input: 300_000)
        Harness.expect(
            !CostPricing.isLongContext(totals: below, model: "gpt-5.6-sol", provider: .codex),
            "100k tokens stays at the base tier"
        )
        Harness.expect(
            CostPricing.isLongContext(totals: above, model: "gpt-5.6-sol", provider: .codex),
            "300k tokens crosses into the long-context tier"
        )
        let baseCost = CostPricing.cost(
            totals: TokenTotals(input: 1_000_000),
            model: "gpt-5.6-sol",
            provider: .codex,
            longContext: false
        )
        let longCost = CostPricing.cost(
            totals: TokenTotals(input: 1_000_000),
            model: "gpt-5.6-sol",
            provider: .codex,
            longContext: true
        )
        Harness.expectEqual(baseCost, 4.0, "sol base input rate")
        Harness.expectEqual(longCost, 8.0, "sol long-context input rate")
    }

    private static func overlayParsing() {
        let overrides = PricingOverlayStore.parseUserOverrides(Data("""
        { "my-model": { "input": 1, "output": 2, "cacheRead": 0.1 } }
        """.utf8))
        Harness.expectEqual(overrides["my-model"]?.input, 1, "user override input rate")

        // models.dev publishes USD per million, keyed provider -> models.
        let catalog = PricingOverlayStore.parseCatalog(Data("""
        {
          "providers": {
            "anthropic": {
              "models": {
                "claude-test-1": {
                  "cost": { "input": 3, "output": 15, "cache_read": 0.3, "cache_write": 3.75 }
                }
              }
            },
            "openai": {
              "models": { "gpt-test-1": { "cost": { "input": 1, "output": 4 } } }
            }
          }
        }
        """.utf8))
        Harness.expectEqual(catalog?["claude-test-1"]?.output, 15, "models.dev output rate")
        Harness.expectEqual(catalog?["gpt-test-1"]?.input, 1, "models.dev second provider parsed")

        // A user override must win over the catalog for the same model.
        let overlay = PricingOverlay(
            userOverrides: ["claude-opus-5": ModelPricing(input: 99, output: 99)],
            modelsDev: ["claude-opus-5": ModelPricing(input: 1, output: 1)]
        )
        Harness.expectEqual(
            CostPricing.pricing(for: "claude-opus-5", provider: .claude, overlay: overlay)?.input,
            99,
            "user override beats the models.dev catalog"
        )
    }

    // MARK: - models.dev refresh

    /// The pricing pane used to wait on this refresh, and a host that cannot reach models.dev
    /// paid the request timeout on every open because a failure writes no cache and so never
    /// stops looking stale. The backoff is what turns that into one attempt an hour.
    private static func catalogRefreshBackoff() {
        let hour: TimeInterval = 60 * 60

        Harness.expect(
            PricingCatalogRefreshPolicy.shouldRefresh(catalogAge: nil, lastAttemptAge: nil),
            "a catalog that was never fetched is worth fetching"
        )
        Harness.expect(
            !PricingCatalogRefreshPolicy.shouldRefresh(catalogAge: 12 * hour, lastAttemptAge: nil),
            "a catalog inside its TTL is left alone"
        )
        Harness.expect(
            PricingCatalogRefreshPolicy.shouldRefresh(catalogAge: 25 * hour, lastAttemptAge: 2 * hour),
            "a catalog past its TTL refreshes once the backoff has run out"
        )
        Harness.expect(
            !PricingCatalogRefreshPolicy.shouldRefresh(catalogAge: nil, lastAttemptAge: 60),
            "a failure a minute ago is not retried"
        )
        Harness.expect(
            PricingCatalogRefreshPolicy.shouldRefresh(catalogAge: nil, lastAttemptAge: 2 * hour),
            "a failure an hour old is retried"
        )
        // A stale catalog still in backoff keeps serving its prices rather than blocking on a
        // fetch; that is the whole point of keeping the old cache on failure.
        Harness.expect(
            !PricingCatalogRefreshPolicy.shouldRefresh(catalogAge: 30 * hour, lastAttemptAge: 5 * 60),
            "a stale catalog waits out the backoff instead of retrying on every call"
        )
    }

    // MARK: - Scanning

    /// A price edit must not rewrite history: what has already been scanned keeps the cost it was
    /// billed at, and the new rate reaches only the turns logged afterwards.
    private static func pricingEditsApplyForward() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agentusagebar-forwardprices-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let codexHome = root.appendingPathComponent("codex")
        let logFile = codexHome.appendingPathComponent("sessions/rollout-forward.jsonl")
        try? FileManager.default.createDirectory(
            at: logFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Stamped now, so the day always lands inside the 30-day window the snapshot covers.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        // 200k input stays under luna's 272k long-context threshold, so the base rate applies.
        let turn = """
        {"type":"turn_context","timestamp":"\(now)","payload":{"model":"gpt-5.6-luna"}}
        {"type":"event_msg","timestamp":"\(now)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0}}}}

        """
        try? turn.write(to: logFile, atomically: true, encoding: .utf8)

        let service = CostService(
            databaseURL: root.appendingPathComponent("cache.sqlite"),
            env: ["CODEX_HOME": codexHome.path, "CLAUDE_CONFIG_DIR": root.appendingPathComponent("claude").path],
            pricingOverlay: PricingOverlay()
        )

        let append = {
            guard let handle = try? FileHandle(forWritingTo: logFile) else { return }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(turn.utf8))
            try? handle.close()
        }

        let before = await service.refresh(.codex)
        Harness.expectClose(before?.windowCostUSD, 0.04, "200k luna tokens at the built-in rate")

        // A turn logged before the edit but not yet scanned still belongs to the old rate.
        append()

        // What the settings pane does on Save: seal what is on disk, then move the rates.
        do {
            try await service.freezeCurrentPrices()
        } catch {
            Harness.expect(false, "freezing prices threw: \(error)")
            return
        }
        await service.usePricingOverlay(PricingOverlay(
            userOverrides: ["gpt-5.6-luna": ModelPricing(input: 5, output: 5)]
        ))

        let sealed = await service.refresh(.codex)
        Harness.expectEqual(sealed?.windowTokens, 400_000, "the pending turn is scanned before the edit")
        Harness.expectClose(sealed?.windowCostUSD, 0.08, "a price edit leaves recorded usage alone")

        append()

        let after = await service.refresh(.codex)
        Harness.expectEqual(after?.windowTokens, 600_000, "the turn logged after the edit is scanned")
        // 0.08 frozen at the old rate plus 200k at the new $5/M rate.
        Harness.expectClose(after?.windowCostUSD, 1.08, "only new usage bills at the new rate")
    }

    private static func scanning() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agentusagebar-costtests-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let codexHome = root.appendingPathComponent("codex")
        let claudeHome = root.appendingPathComponent("claude")
        let codexFile = codexHome.appendingPathComponent("sessions/2026/08/26/rollout-test.jsonl")
        let claudeFile = claudeHome.appendingPathComponent("projects/demo/session.jsonl")
        for url in [codexFile, claudeFile] {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        let day = "2026-08-26T10:00:00.000Z"
        // turn_context names the model; each token_count carries that turn's delta.
        // A real day mixes models: turn_context announces the model for the turns that follow.
        let solTurn = #"{"type":"event_msg","timestamp":"\#(day)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0}}}}"#
        let codexLines = [
            #"{"type":"turn_context","timestamp":"\#(day)","payload":{"model":"gpt-5.6-sol"}}"#,
            solTurn,
            #"{"type":"turn_context","timestamp":"\#(day)","payload":{"model":"gpt-5.6-luna"}}"#,
            solTurn,
        ]
        let claudeLines = [
            #"{"type":"assistant","timestamp":"\#(day)","requestId":"req-1","uuid":"u1","message":{"id":"msg-1","model":"claude-opus-5","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#,
            // Same message replayed into the same transcript must be counted once.
            #"{"type":"assistant","timestamp":"\#(day)","requestId":"req-1","uuid":"u2","message":{"id":"msg-1","model":"claude-opus-5","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#,
        ]
        try? (codexLines.joined(separator: "\n") + "\n").write(to: codexFile, atomically: true, encoding: .utf8)
        try? (claudeLines.joined(separator: "\n") + "\n").write(to: claudeFile, atomically: true, encoding: .utf8)

        let env = ["CODEX_HOME": codexHome.path, "CLAUDE_CONFIG_DIR": claudeHome.path]
        let service = CostService(
            databaseURL: root.appendingPathComponent("cache.sqlite"),
            env: env,
            pricingOverlay: PricingOverlay()
        )

        let codex = await service.refresh(.codex)
        // 200k input tokens stays under sol's 270k long-context threshold, so the base rate
        // applies: 200k at $4/M for sol plus 200k at $0.20/M for luna.
        Harness.expectEqual(codex?.windowTokens, 400_000, "codex tokens scanned")
        Harness.expectClose(codex?.windowCostUSD, 0.84, "codex cost across two models")
        Harness.expectEqual(codex?.topModel, "gpt-5.6-sol", "codex top model")

        // The hover breakdown needs each model's own share, ranked by cost.
        let breakdown = codex?.days.first
        Harness.expectEqual(breakdown?.byModel.count, 2, "both models appear in the day breakdown")
        Harness.expectEqual(
            breakdown?.rankedModels.first?.model,
            "gpt-5.6-sol",
            "the costlier model ranks first"
        )
        Harness.expectClose(breakdown?.rankedModels.first?.usage.costUSD, 0.8, "per-model cost for sol")
        Harness.expectClose(breakdown?.rankedModels.last?.usage.costUSD, 0.04, "per-model cost for luna")

        let claude = await service.refresh(.claude)
        // The duplicated message must not double the total.
        Harness.expectEqual(claude?.windowTokens, 1_000_000, "claude dedupes a replayed message")
        Harness.expectEqual(claude?.windowCostUSD, 5.0, "claude cost at the opus-5 input rate")

        // Scanning Claude must not evict Codex's rows: each scanner only knows its own roots, so
        // an unscoped prune would wipe the other provider every refresh.
        let codexAfter = await service.refresh(.codex)
        Harness.expectEqual(codexAfter?.windowTokens, 400_000, "codex survives a Claude scan")

        // Appending must add to the totals rather than restate them, and the appended turn must
        // land on the model named by the last turn_context -- which a resumed scan has to recover
        // by rereading the turn_context lines it already skipped past.
        let appended = solTurn + "\n"
        if let handle = try? FileHandle(forWritingTo: codexFile) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(appended.utf8))
            try? handle.close()
        }
        let codexGrown = await service.refresh(.codex)
        Harness.expectEqual(codexGrown?.windowTokens, 600_000, "appended turns are picked up incrementally")
        Harness.expectClose(
            codexGrown?.days.first?.byModel["gpt-5.6-luna"]?.costUSD,
            0.08,
            "a resumed scan attributes the appended turn to the last announced model"
        )
        let modelUsage = await service.knownModelUsage(provider: .codex)
        Harness.expectEqual(modelUsage.first?.model, "gpt-5.6-luna", "pricing models sort by token usage")
        Harness.expectEqual(modelUsage.first?.tokens, 400_000, "pricing model usage carries token totals")

        await Self.claudeStreamingChunksKeepTheFinalOutput(root: root)
        await Self.claudeOneHourCacheWritesCostDouble(root: root)
        await Self.codexSkipsReEmittedTokenCounts(root: root)
        await Self.codexCacheBucketsAreCarvedOutOfInput(root: root)
        await Self.pricingChangesOnlyAffectNewUsage(root: root)
    }

    /// Claude writes an assistant message several times while it streams. The prompt figures are
    /// final from the first chunk, but output_tokens grows, so the last chunk is the honest one.
    private static func claudeStreamingChunksKeepTheFinalOutput(root: URL) async {
        let projects = root.appendingPathComponent("stream-claude/projects/app")
        try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let file = projects.appendingPathComponent("session.jsonl")

        func line(output: Int) -> String {
            #"{"type":"assistant","timestamp":"2026-08-26T15:00:00.000Z","requestId":"req-1","message":{"id":"msg-1","model":"stream-model","usage":{"input_tokens":1000000,"output_tokens":\#(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
        }
        // A partial chunk, then the finished reply, then the same message replayed into a fork.
        let lines = [line(output: 3), line(output: 2_000_000), line(output: 2_000_000)]
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)

        let service = CostService(
            databaseURL: root.appendingPathComponent("stream-cache.sqlite"),
            env: ["CLAUDE_CONFIG_DIR": root.appendingPathComponent("stream-claude").path],
            pricingOverlay: PricingOverlay(userOverrides: [
                "stream-model": ModelPricing(input: 1, output: 2),
            ])
        )
        let snapshot = await service.refresh(.claude)
        // $1 of prompt and $4 of reply, counted once: the partial chunk and the replay both lose.
        Harness.expectClose(
            snapshot?.windowCostUSD,
            5,
            "a streamed message is billed once, at the output count of its final chunk"
        )
        Harness.expectEqual(
            snapshot?.windowTokens,
            3_000_000,
            "replaying a finished message does not add its tokens again"
        )
    }

    /// Anthropic bills a one-hour cache write at twice the input rate and a five-minute one at
    /// 1.25x, so the two TTLs cannot share the table's single cache-write column.
    private static func claudeOneHourCacheWritesCostDouble(root: URL) async {
        let projects = root.appendingPathComponent("ttl-claude/projects/app")
        try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let file = projects.appendingPathComponent("session.jsonl")

        func line(_ id: String, fiveMinute: Int, oneHour: Int) -> String {
            #"{"type":"assistant","timestamp":"2026-08-26T14:00:00.000Z","requestId":"req-\#(id)","message":{"id":"msg-\#(id)","model":"ttl-model","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":\#(fiveMinute + oneHour),"cache_creation":{"ephemeral_5m_input_tokens":\#(fiveMinute),"ephemeral_1h_input_tokens":\#(oneHour)},"cache_read_input_tokens":0}}}"#
        }
        let lines = [
            line("a", fiveMinute: 1_000_000, oneHour: 0),
            line("b", fiveMinute: 0, oneHour: 1_000_000),
        ]
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)

        let service = CostService(
            databaseURL: root.appendingPathComponent("ttl-cache.sqlite"),
            env: ["CLAUDE_CONFIG_DIR": root.appendingPathComponent("ttl-claude").path],
            pricingOverlay: PricingOverlay(userOverrides: [
                "ttl-model": ModelPricing(input: 10, output: 0, cacheWrite: 12.5, cacheRead: 0),
            ])
        )
        let snapshot = await service.refresh(.claude)
        // 1M at the 12.5 five-minute rate + 1M at 2x the 10 input rate = $32.50.
        Harness.expectClose(
            snapshot?.windowCostUSD,
            32.5,
            "a one-hour cache write costs twice input while a five-minute one uses the table rate"
        )
        Harness.expectEqual(
            snapshot?.windowTokens,
            2_000_000,
            "the one-hour subset is not counted a second time in the token total"
        )
    }

    /// Codex re-emits a token_count when its rate-limit block refreshes. The replay repeats the
    /// previous last_token_usage while total_token_usage stands still, and must not be counted.
    private static func codexSkipsReEmittedTokenCounts(root: URL) async {
        let home = root.appendingPathComponent("replay-codex")
        let file = home.appendingPathComponent("sessions/2026/08/26/rollout-replay.jsonl")
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        func event(_ time: String, last: Int, total: Int) -> String {
            #"{"type":"event_msg","timestamp":"\#(time)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\#(last),"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0},"total_token_usage":{"input_tokens":\#(total),"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0}}}}"#
        }
        let context = #"{"type":"turn_context","timestamp":"2026-08-26T13:00:00.000Z","payload":{"model":"replay-model"}}"#
        let lines = [
            context,
            event("2026-08-26T13:00:01.000Z", last: 1_000_000, total: 1_000_000),
            event("2026-08-26T13:00:02.000Z", last: 1_000_000, total: 2_000_000),
            // Same running total as the line above: a re-emission, not a third turn.
            event("2026-08-26T13:00:03.000Z", last: 1_000_000, total: 2_000_000),
        ]
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)

        let database = root.appendingPathComponent("replay-cache.sqlite")
        let env = ["CODEX_HOME": home.path]
        let overlay = PricingOverlay(userOverrides: [
            "replay-model": ModelPricing(input: 1, output: 1),
        ])
        let snapshot = await CostService(databaseURL: database, env: env, pricingOverlay: overlay)
            .refresh(.codex)
        Harness.expectClose(
            snapshot?.windowCostUSD,
            2,
            "a re-emitted token_count is not counted as another turn"
        )

        // The replay is the last line, so a resumed scan has to recognise it across the boundary.
        let appended = event("2026-08-26T13:00:04.000Z", last: 1_000_000, total: 2_000_000)
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((appended + "\n").utf8))
            try? handle.close()
        }
        let resumed = await CostService(databaseURL: database, env: env, pricingOverlay: overlay)
            .refresh(.codex)
        Harness.expectClose(
            resumed?.windowCostUSD,
            2,
            "a resumed scan still recognises a replay of the turn it stopped on"
        )
    }

    /// Codex counts cached reads and cache writes inside input_tokens, so a turn that reports all
    /// three must not be billed for the same token twice.
    private static func codexCacheBucketsAreCarvedOutOfInput(root: URL) async {
        let home = root.appendingPathComponent("carve-codex")
        let file = home.appendingPathComponent("sessions/2026/08/26/rollout-carve.jsonl")
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let timestamp = "2026-08-26T12:00:00.000Z"
        let context = #"{"type":"turn_context","timestamp":"\#(timestamp)","payload":{"model":"carve-model"}}"#
        // 1,000,000 prompt tokens: 600k served from cache, 100k written to it, 300k fresh.
        let usage = #"{"type":"event_msg","timestamp":"\#(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000000,"cached_input_tokens":600000,"cache_write_input_tokens":100000,"output_tokens":0}}}}"#
        try? ([context, usage].joined(separator: "\n") + "\n")
            .write(to: file, atomically: true, encoding: .utf8)

        let service = CostService(
            databaseURL: root.appendingPathComponent("carve-cache.sqlite"),
            env: ["CODEX_HOME": home.path],
            pricingOverlay: PricingOverlay(userOverrides: [
                "carve-model": ModelPricing(input: 10, output: 0, cacheWrite: 1, cacheRead: 0),
            ])
        )
        let snapshot = await service.refresh(.codex)
        // 300k fresh at $10/M + 100k written at $1/M + 600k read at $0/M = $3.10.
        Harness.expectClose(
            snapshot?.windowCostUSD,
            3.1,
            "cached reads and cache writes are peeled out of input_tokens before pricing"
        )
        Harness.expectEqual(
            snapshot?.windowTokens,
            1_000_000,
            "peeling the buckets apart preserves the turn's total token count"
        )
    }

    /// Editing a custom rate is prospective: usage already scanned keeps the price that was in
    /// force, while bytes appended afterward use the new rate.
    private static func pricingChangesOnlyAffectNewUsage(root: URL) async {
        let home = root.appendingPathComponent("versioned-codex")
        let file = home.appendingPathComponent("sessions/2026/08/26/rollout-pricing.jsonl")
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let timestamp = "2026-08-26T11:00:00.000Z"
        let context = #"{"type":"turn_context","timestamp":"\#(timestamp)","payload":{"model":"custom-model"}}"#
        let usage = #"{"type":"event_msg","timestamp":"\#(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0}}}}"#
        try? ([context, usage].joined(separator: "\n") + "\n")
            .write(to: file, atomically: true, encoding: .utf8)

        let database = root.appendingPathComponent("versioned-cache.sqlite")
        let env = ["CODEX_HOME": home.path]
        let originalService = CostService(
            databaseURL: database,
            env: env,
            pricingOverlay: PricingOverlay(
                userOverrides: ["custom-model": ModelPricing(input: 1, output: 1)]
            )
        )
        let original = await originalService.refresh(.codex)
        Harness.expectClose(original?.windowCostUSD, 1, "original usage uses the original custom rate")

        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((usage + "\n").utf8))
            try? handle.close()
        }

        let updatedService = CostService(
            databaseURL: database,
            env: env,
            pricingOverlay: PricingOverlay(
                userOverrides: ["custom-model": ModelPricing(input: 2, output: 1)]
            )
        )
        let updated = await updatedService.refresh(.codex)
        Harness.expectClose(
            updated?.windowCostUSD,
            3,
            "a changed custom rate only prices usage appended after the change"
        )
    }
}

/// Rate-limit gate checks. The quota endpoints are shared with the CLIs, so a 429 has to stop
/// further requests until the window passes.
enum RateLimitTests {
    static func run() async {
        let gate = UsageRateLimitGate()
        let now = Date()

        Harness.expect(await gate.blocked(.claude, now: now) == nil, "a fresh gate blocks nothing")

        // No Retry-After: fall back to the default backoff.
        await gate.recordRateLimit(.claude, retryAfter: nil, now: now)
        let blocked = await gate.blocked(.claude, now: now)
        Harness.expect(blocked != nil, "a recorded 429 blocks the provider")
        Harness.expectEqual(
            blocked.map { Int($0.timeIntervalSince(now).rounded()) },
            300,
            "default backoff is five minutes"
        )

        // The other provider must be unaffected.
        Harness.expect(await gate.blocked(.codex, now: now) == nil, "the gate is per provider")

        // The window lifts on its own once it passes.
        Harness.expect(
            await gate.blocked(.claude, now: now.addingTimeInterval(301)) == nil,
            "the block expires after its window"
        )

        // A longer server-supplied window is honoured; a shorter one is floored at the default,
        // because we only get here by having asked too often already.
        await gate.recordRateLimit(.claude, retryAfter: now.addingTimeInterval(1800), now: now)
        Harness.expectEqual(
            (await gate.blocked(.claude, now: now)).map { Int($0.timeIntervalSince(now).rounded()) },
            1800,
            "a longer Retry-After is honoured"
        )
        await gate.recordRateLimit(.codex, retryAfter: now.addingTimeInterval(30), now: now)
        Harness.expectEqual(
            (await gate.blocked(.codex, now: now)).map { Int($0.timeIntervalSince(now).rounded()) },
            300,
            "a shorter Retry-After is floored at the default backoff"
        )

        await gate.recordSuccess(.claude)
        Harness.expect(await gate.blocked(.claude, now: now) == nil, "a success clears the block")
    }
}

/// One cooldown for every refresh path, so a poll and a click cannot both hit the endpoints.
enum RefreshCooldownGateTests {
    static func run() {
        var gate = RefreshCooldownGate()

        Harness.expect(gate.claimRefresh(at: 1_000), "the first refresh runs")
        Harness.expect(!gate.claimRefresh(at: 1_001), "a click right after does not refresh")
        Harness.expect(!gate.claimRefresh(at: 1_058.9), "the cooldown lasts about a minute")
        Harness.expect(gate.claimRefresh(at: 1_059), "the scheduling tolerance lets a 60s poll through")
        Harness.expect(!gate.claimRefresh(at: 1_060), "the refreshed cooldown starts over")

        // A forced refresh answers a settings change rather than a tick, but it still quiets the
        // minute after it.
        var forced = RefreshCooldownGate()
        Harness.expect(forced.claimRefresh(at: 2_000), "the first refresh runs")
        forced.recordRefresh(at: 2_030)
        Harness.expect(!forced.claimRefresh(at: 2_059), "a forced refresh restarts the cooldown")
        Harness.expect(forced.claimRefresh(at: 2_089), "and the cooldown runs from the forced refresh")

        // A cadence faster than the cooldown would otherwise drop ticks; the tolerance is only
        // slack for scheduling, not a second knob.
        var tight = RefreshCooldownGate(minimumInterval: 10, tolerance: 0)
        Harness.expect(tight.claimRefresh(at: 0), "the first refresh runs")
        Harness.expect(!tight.claimRefresh(at: 9.999), "a custom interval is honoured")
        Harness.expect(tight.claimRefresh(at: 10), "and elapses exactly")
    }
}

/// What the Refresh row says while the cooldown runs.
enum RefreshRowPolicyTests {
    static func run() {
        let idle = RefreshRowPolicy.state(cooldownRemaining: 0, isRefreshing: false)
        Harness.expectEqual(idle.title, "Refresh", "an elapsed cooldown leaves the plain title")
        Harness.expectEqual(idle.trailingText, nil, "an elapsed cooldown leaves the shortcut column empty")
        Harness.expect(idle.isEnabled, "and the row accepts clicks")

        let waiting = RefreshRowPolicy.state(cooldownRemaining: 42, isRefreshing: false)
        Harness.expectEqual(waiting.title, "Refresh", "the cooldown keeps the plain title")
        Harness.expectEqual(waiting.trailingText, "42s", "the cooldown is spelled out in the shortcut column")
        Harness.expect(!waiting.isEnabled, "and the row refuses clicks it would drop")

        // Rounded up, so the last partial second never reads as a refresh that would be honoured.
        let sliver = RefreshRowPolicy.state(cooldownRemaining: 0.2, isRefreshing: false)
        Harness.expectEqual(sliver.title, "Refresh", "a partial second keeps the plain title")
        Harness.expectEqual(sliver.trailingText, "1s", "a partial second still counts")
        Harness.expect(!sliver.isEnabled, "and still refuses clicks")

        // An in-flight refresh holds the cooldown too, but a countdown would misdescribe it.
        let running = RefreshRowPolicy.state(cooldownRemaining: 59, isRefreshing: true)
        Harness.expectEqual(running.title, "Refreshing…", "a running refresh says so")
        Harness.expectEqual(running.trailingText, nil, "a running refresh leaves the shortcut column empty")
        Harness.expect(!running.isEnabled, "and the row refuses a second one")
    }
}

/// Settings persistence and the refresh cadence table.
enum SettingsTests {
    @MainActor
    static func run() {
        // Fixed rather than PID-stamped: a name that changes per run leaves a new plist behind
        // in ~/Library/Preferences every time, since emptying a domain does not remove its file.
        let suite = "AgentUsageBarTests"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // Five minutes by default: the quota endpoints rate-limit, so a faster default would
        // reintroduce the 429 this cadence exists to avoid.
        let store = SettingsStore(defaults: defaults)
        Harness.expectEqual(store.refreshFrequency, .fiveMinutes, "default cadence")
        Harness.expectEqual(store.menuBarProvider, Provider.allCases[0], "one provider shows by default")
        Harness.expectEqual(store.costChartLabelMode, .tokens, "chart labels default to tokens")
        // The countdown is the reading nobody has to be taught, so it stays the one on first open.
        Harness.expectEqual(
            store.quotaResetDisplayMode,
            .countdown,
            "reset labels default to the countdown"
        )
        Harness.expectEqual(
            QuotaResetDisplayMode.countdown.toggled,
            .clock,
            "a click swaps the countdown for the clock"
        )
        Harness.expectEqual(
            QuotaResetDisplayMode.clock.toggled,
            .countdown,
            "a second click swaps back"
        )

        Harness.expectEqual(RefreshFrequency.manual.seconds, nil, "manual runs no timer")
        Harness.expectEqual(RefreshFrequency.oneMinute.seconds, 60, "one minute in seconds")
        Harness.expectEqual(RefreshFrequency.thirtyMinutes.seconds, 1800, "thirty minutes in seconds")
        Harness.expectEqual(RefreshFrequency.allCases.count, 6, "six cadence options")

        // A right-click publishes exactly one provider, and cycling wraps back around.
        var switches: [Provider] = []
        let observer = store.$menuBarProvider
            .dropFirst()
            .sink { switches.append($0) }

        store.refreshFrequency = .fifteenMinutes
        store.advanceMenuBarProvider()
        store.advanceMenuBarProvider()
        Harness.expectEqual(
            switches,
            [MenuBarProviderPolicy.next(after: Provider.allCases[0]), Provider.allCases[0]],
            "each right-click publishes the next provider"
        )
        _ = observer

        store.menuBarProvider = .claude
        store.costChartLabelMode = .cost
        store.quotaResetDisplayMode = .clock

        let reloaded = SettingsStore(defaults: defaults)
        Harness.expectEqual(reloaded.refreshFrequency, .fifteenMinutes, "cadence survives a reload")
        Harness.expectEqual(reloaded.menuBarProvider, .claude, "the shown provider survives a reload")
        Harness.expectEqual(reloaded.costChartLabelMode, .cost, "chart label mode survives a reload")
        reloaded.costChartLabelMode = .tokens
        Harness.expectEqual(
            SettingsStore(defaults: defaults).costChartLabelMode,
            .tokens,
            "chart label mode can switch back to tokens"
        )
        Harness.expectEqual(
            reloaded.quotaResetDisplayMode,
            .clock,
            "the reset label face survives a reload"
        )

        // A machine upgrading from the two-toggle build keeps the item it had left enabled.
        let legacySuite = "\(suite)-legacy"
        let legacyDefaults = UserDefaults(suiteName: legacySuite) ?? .standard
        legacyDefaults.removePersistentDomain(forName: legacySuite)
        defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }
        legacyDefaults.set(false, forKey: "provider.codex.enabled")
        legacyDefaults.set(true, forKey: "provider.claude.enabled")
        Harness.expectEqual(
            SettingsStore(defaults: legacyDefaults).menuBarProvider,
            .claude,
            "the single remaining legacy item becomes the shown provider"
        )
    }
}

/// The menu bar shows one provider at a time, and a right-click walks the list.
enum MenuBarProviderTests {
    static func run() {
        // Cycling reaches every provider and wraps, so it never dead-ends on the last one.
        var provider = Provider.allCases[0]
        var walk: [Provider] = []
        for _ in Provider.allCases {
            provider = MenuBarProviderPolicy.next(after: provider)
            walk.append(provider)
        }
        Harness.expectEqual(Set(walk), Set(Provider.allCases), "cycling reaches every provider")
        Harness.expectEqual(walk.last, Provider.allCases[0], "cycling wraps back to the first")
    }
}

/// Pace projection: expected usage is linear in elapsed window time, and the delta against
/// actual usage becomes the deficit/reserve line under each bar.
enum PaceTests {
    private static let week: TimeInterval = 7 * 24 * 3600
    private static let weekMinutes = 10_080

    private static func window(used: Double, secondsUntilReset: TimeInterval, now: Date) -> UsageWindow {
        UsageWindow(
            usedPercent: used,
            resetsAt: now.addingTimeInterval(secondsUntilReset),
            windowSeconds: Self.weekMinutes * 60
        )
    }

    /// Plain "1d 12h" rendering so the label assertions do not depend on the UI formatter.
    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h"
    }

    static func run() {
        let now = Date()

        // Halfway through the window with half the budget spent is exactly on pace.
        let onPace = UsagePace.evaluate(
            window: Self.window(used: 50, secondsUntilReset: Self.week / 2, now: now),
            context: .weekly,
            now: now
        )
        Harness.expectEqual(onPace?.stage, .onTrack, "half spent at halfway is on track")
        Harness.expectEqual(onPace?.deltaLabel, "On pace", "on-track label")

        // Spending faster than the clock is a deficit, and the budget empties before the reset.
        let deficit = UsagePace.evaluate(
            window: Self.window(used: 70, secondsUntilReset: Self.week / 2, now: now),
            context: .weekly,
            now: now
        )
        Harness.expectEqual(deficit?.stage, .farAhead, "20 points over expected is far ahead")
        Harness.expectEqual(deficit?.deltaLabel, "20% in deficit", "deficit label")
        Harness.expect(deficit?.willLastToReset == false, "a deficit does not last to the reset")
        Harness.expectEqual(
            deficit?.etaLabel(context: .weekly, durationText: Self.duration),
            "Runs out in 1d 12h",
            "weekly ETA wording"
        )
        // The session window says "projected empty" rather than "runs out".
        Harness.expectEqual(
            deficit?.etaLabel(context: .session, durationText: Self.duration),
            "Projected empty in 1d 12h",
            "session ETA wording"
        )

        // Spending slower banks a reserve, and the headroom hint appears past 15 points.
        let reserve = UsagePace.evaluate(
            window: Self.window(used: 30, secondsUntilReset: Self.week / 2, now: now),
            context: .weekly,
            now: now
        )
        Harness.expectEqual(reserve?.stage, .farBehind, "20 points under expected is far behind")
        Harness.expectEqual(reserve?.deltaLabel, "20% in reserve", "reserve label")
        Harness.expect(reserve?.willLastToReset == true, "a reserve lasts to the reset")
        Harness.expectEqual(
            reserve?.etaLabel(context: .weekly, durationText: Self.duration),
            "Lasts until reset · 1.5× headroom",
            "headroom hint at a large reserve"
        )

        // A small reserve gets the plain label, with no headroom claim.
        let smallReserve = UsagePace.evaluate(
            window: Self.window(used: 45, secondsUntilReset: Self.week / 2, now: now),
            context: .weekly,
            now: now
        )
        Harness.expectEqual(smallReserve?.stage, .slightlyBehind, "5 points under is slightly behind")
        Harness.expectEqual(
            smallReserve?.etaLabel(context: .weekly, durationText: Self.duration),
            "Lasts until reset",
            "no headroom hint for a small reserve"
        )

        // The bar shows what is left, so the tip is placed on the remaining side.
        Harness.expectEqual(onPace?.expectedRemainingPercent, 50, "pace tip position mirrors expected use")

        // Guards: each of these would produce a misleading reading.
        Harness.expect(
            UsagePace.evaluate(
                window: UsageWindow(usedPercent: 50, resetsAt: nil, windowSeconds: nil),
                context: .weekly,
                now: now
            ) == nil,
            "no reset time means no pace"
        )
        Harness.expect(
            UsagePace.evaluate(
                window: Self.window(used: 100, secondsUntilReset: Self.week / 2, now: now),
                context: .weekly,
                now: now
            ) == nil,
            "an exhausted window has no pace to report"
        )
        Harness.expect(
            UsagePace.evaluate(
                window: Self.window(used: 50, secondsUntilReset: -60, now: now),
                context: .weekly,
                now: now
            ) == nil,
            "a reset in the past is rejected"
        )
        Harness.expect(
            UsagePace.evaluate(
                window: Self.window(used: 50, secondsUntilReset: Self.week * 2, now: now),
                context: .weekly,
                now: now
            ) == nil,
            "a reset further out than one window is rejected"
        )
        // Just after a reset the expected figure is rounding noise, so nothing is shown.
        Harness.expect(
            UsagePace.evaluate(
                window: Self.window(used: 1, secondsUntilReset: Self.week * 0.99, now: now),
                context: .weekly,
                now: now
            ) == nil,
            "under 3% elapsed is too early to judge"
        )

        // Stage boundaries, straight from CodexBar's thresholds.
        Harness.expectEqual(UsagePace.stage(for: 2), .onTrack, "2 points is still on track")
        Harness.expectEqual(UsagePace.stage(for: 6), .slightlyAhead, "6 points is slightly ahead")
        Harness.expectEqual(UsagePace.stage(for: -12), .behind, "12 points under is behind")
        Harness.expectEqual(UsagePace.stage(for: 12.1), .farAhead, "past 12 points is far ahead")
    }
}

/// The historical pace model: sampling, week reconstruction, and the regression that replaces
/// the linear expectation once enough complete windows exist.
enum HistoricalPaceTests {
    private static let weekSeconds: TimeInterval = 7 * 24 * 3600
    private static let weekMinutes = 10_080

    /// A synthetic completed window whose usage follows `shape(u)`, sampled at 11 points so it
    /// clears both the sample-count floor and the boundary-coverage test.
    private static func records(
        resetsAt: Date,
        shape: (Double) -> Double
    ) -> [UsageHistoryRecord] {
        let windowStart = resetsAt.addingTimeInterval(-Self.weekSeconds)
        return stride(from: 0.0, through: 1.0, by: 0.1).map { u in
            UsageHistoryRecord(
                provider: .codex,
                sampledAt: windowStart.addingTimeInterval(u * Self.weekSeconds),
                usedPercent: shape(u),
                resetsAt: resetsAt,
                windowMinutes: Self.weekMinutes
            )
        }
    }

    static func run() {
        Self.samplingGate()
        Self.curveReconstruction()
        Self.completeness()
        Self.helpers()
        Self.regression()
    }

    private static func samplingGate() {
        let now = Date()
        let base = UsageHistoryRecord(
            provider: .codex,
            sampledAt: now,
            usedPercent: 40,
            resetsAt: now.addingTimeInterval(Self.weekSeconds),
            windowMinutes: Self.weekMinutes
        )
        Harness.expect(UsageHistoryStore.shouldWrite(base, after: nil), "the first sample is always kept")

        // Same reading a few minutes later is not worth a row.
        let soon = UsageHistoryRecord(
            provider: .codex,
            sampledAt: now.addingTimeInterval(300),
            usedPercent: 40.2,
            resetsAt: base.resetsAt,
            windowMinutes: Self.weekMinutes
        )
        Harness.expect(!UsageHistoryStore.shouldWrite(soon, after: base), "a tiny change soon after is skipped")

        // A whole point of movement is worth recording immediately.
        let moved = UsageHistoryRecord(
            provider: .codex,
            sampledAt: now.addingTimeInterval(300),
            usedPercent: 41.5,
            resetsAt: base.resetsAt,
            windowMinutes: Self.weekMinutes
        )
        Harness.expect(UsageHistoryStore.shouldWrite(moved, after: base), "a one-point move is recorded")

        // And so is the passage of the write interval.
        let later = UsageHistoryRecord(
            provider: .codex,
            sampledAt: now.addingTimeInterval(31 * 60),
            usedPercent: 40.1,
            resetsAt: base.resetsAt,
            windowMinutes: Self.weekMinutes
        )
        Harness.expect(UsageHistoryStore.shouldWrite(later, after: base), "the write interval forces a sample")
    }

    private static func curveReconstruction() {
        let resetsAt = Date()
        let windowStart = resetsAt.addingTimeInterval(-Self.weekSeconds)
        // A dip mid-week must not survive: cumulative usage only goes up.
        let samples = Self.records(resetsAt: resetsAt) { u in u < 0.5 ? u * 100 : max(0, 50 - (u - 0.5) * 20) }
        guard let curve = UsageHistoryStore.reconstructCurve(
            samples: samples,
            windowStart: windowStart,
            duration: Self.weekSeconds
        ) else {
            Harness.expect(false, "curve reconstruction returned nil")
            return
        }

        Harness.expectEqual(curve.count, UsageWeekProfile.gridPointCount, "curve lands on the fixed grid")
        Harness.expectEqual(curve.first, 0, "the curve is anchored at zero on the window start")
        Harness.expect(
            zip(curve, curve.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 },
            "the curve is monotone despite a dip in the samples"
        )
        Harness.expect(curve.last! >= 49.9, "the curve holds the peak through the reset")
    }

    private static func completeness() {
        let resetsAt = Date()
        let windowStart = resetsAt.addingTimeInterval(-Self.weekSeconds)
        let full = Self.records(resetsAt: resetsAt) { $0 * 100 }
        Harness.expect(
            UsageHistoryStore.isComplete(samples: full, windowStart: windowStart, resetsAt: resetsAt),
            "a fully sampled window is complete"
        )

        // Too few samples cannot describe a shape.
        Harness.expect(
            !UsageHistoryStore.isComplete(
                samples: Array(full.prefix(3)),
                windowStart: windowStart,
                resetsAt: resetsAt
            ),
            "three samples is not a complete window"
        )

        // A window first observed on day five would look like a very light week.
        let lateOnly = full.filter { $0.sampledAt.timeIntervalSince(windowStart) > 5 * 86_400 }
        Harness.expect(
            !UsageHistoryStore.isComplete(samples: lateOnly, windowStart: windowStart, resetsAt: resetsAt),
            "a window missing its start is rejected"
        )

        // Incomplete weeks must not reach the dataset at all.
        let dataset = UsageHistoryStore.buildDataset(from: Array(full.prefix(3)))
        Harness.expect(dataset == nil, "an incomplete week yields no dataset")
    }

    private static func helpers() {
        Harness.expectEqual(
            HistoricalUsagePace.interpolate(curve: [0, 50, 100], at: 0.25),
            25,
            "interpolation between grid points"
        )
        Harness.expectEqual(
            HistoricalUsagePace.weightedMedian(values: [10, 20, 30], weights: [1, 1, 8]),
            30,
            "weight dominates the median"
        )
        Harness.expectEqual(
            HistoricalUsagePace.weightedMedian(values: [10, 20, 30], weights: [1, 1, 1]),
            20,
            "equal weights give the plain median"
        )

        // A week that hit the cap early carries no rate information past that point, so the
        // tail is replaced by the average slope that got it there.
        let capped = [0.0, 50.0, 100.0, 100.0, 100.0]
        let extended = HistoricalUsagePace.extendPastCap(capped)
        Harness.expect(extended.last! > 100, "the capped tail is extrapolated past the cap")

        // Crossing detection: a curve shifted to meet current usage reaches 100 partway.
        let crossing = HistoricalUsagePace.firstCrossing(
            after: 0,
            curve: [0, 25, 50, 75, 100],
            shift: 50,
            actualAtNow: 50
        )
        Harness.expect(crossing != nil, "a shifted curve that reaches the cap reports a crossing")
        Harness.expect((crossing ?? 1) <= 0.55, "the crossing lands where the shifted curve hits 100")
    }

    private static func regression() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(Self.weekSeconds / 2)
        let current = UsageWindow(
            usedPercent: 50,
            resetsAt: resetsAt,
            windowSeconds: Self.weekMinutes * 60
        )

        // Past weeks that spend late: 20% by mid-week, everything by the reset.
        func backLoaded(_ weeksAgo: Int) -> [UsageHistoryRecord] {
            Self.records(resetsAt: resetsAt.addingTimeInterval(-Double(weeksAgo) * Self.weekSeconds)) { u in
                u <= 0.5 ? u * 40 : 20 + (u - 0.5) * 160
            }
        }

        // Two weeks of history is not enough to displace the linear model.
        let thin = UsageHistoryStore.buildDataset(from: (1...2).flatMap(backLoaded))
        Harness.expect(
            HistoricalUsagePace.evaluate(window: current, dataset: thin, now: now) == nil,
            "under three weeks the historical model stays silent"
        )

        guard let four = UsageHistoryStore.buildDataset(from: (1...4).flatMap(backLoaded)),
              let pace = HistoricalUsagePace.evaluate(window: current, dataset: four, now: now) else {
            Harness.expect(false, "four weeks of history should produce a pace")
            return
        }
        Harness.expectEqual(four.weeks.count, 4, "four complete weeks are recognised")
        // Halfway through, history says 20% is normal, so 50% spent is a deficit -- where the
        // linear model would have called this exactly on pace.
        Harness.expect(pace.expectedUsedPercent < 50, "history lowers the expectation below linear")
        Harness.expect(pace.stage.isAhead, "spending at the linear rate reads as a deficit here")
        Harness.expect(pace.runOutProbability == nil, "risk needs five weeks, not four")

        guard let five = UsageHistoryStore.buildDataset(from: (1...5).flatMap(backLoaded)),
              let withRisk = HistoricalUsagePace.evaluate(window: current, dataset: five, now: now) else {
            Harness.expect(false, "five weeks of history should produce a pace")
            return
        }
        Harness.expect(withRisk.runOutProbability != nil, "five weeks unlocks the risk figure")

        // Every past week ran the window dry from here, so this one is projected to as well.
        Harness.expect(!withRisk.willLastToReset, "a history of running dry projects running dry")
        Harness.expect(withRisk.etaSeconds != nil, "a projected run-out carries an ETA")
    }
}

/// The hand-edited price layer: round-trips through disk and outranks the other layers.
enum PricingOverrideTests {
    static func run() {
        let url = PricingOverlayStore.userOverridesURL
        // Never clobber a real override file while testing.
        let backup = try? Data(contentsOf: url)
        defer {
            if let backup {
                try? backup.write(to: url)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let overrides: [String: ModelPricing] = [
            "ox-alpha": ModelPricing(input: 1.5, output: 6, cacheWrite: 1.875, cacheRead: 0.15),
            "claude-opus-5": ModelPricing(input: 99, output: 99),
            // Everything the billing math reads, so an override cannot silently drop a tier.
            "ox-tiered": ModelPricing(
                input: 2, output: 12, cacheWrite: 2.5, cacheWrite1h: 3.5, cacheRead: 0.2,
                thresholdTokens: 200_000,
                inputAbove: 4, outputAbove: 18, cacheWriteAbove: 5,
                cacheWrite1hAbove: 7, cacheReadAbove: 0.4
            ),
        ]
        do {
            try PricingOverlayStore.saveUserOverrides(overrides)
        } catch {
            Harness.expect(false, "saving overrides threw: \(error)")
            return
        }

        let loaded = PricingOverlayStore.loadUserOverrides()
        Harness.expectEqual(loaded["ox-alpha"]?.input, 1.5, "override input rate round-trips")
        Harness.expectEqual(loaded["ox-alpha"]?.cacheRead, 0.15, "override cache rate round-trips")
        Harness.expectEqual(loaded.count, 3, "every override round-trips")
        Harness.expectEqual(loaded["ox-tiered"], overrides["ox-tiered"], "the full rate set round-trips")

        // A model with no built-in price becomes priceable through the override alone.
        let overlay = PricingOverlay(userOverrides: loaded, modelsDev: [:])
        Harness.expectEqual(
            CostPricing.cost(
                totals: TokenTotals(input: 1_000_000),
                model: "ox-alpha",
                provider: .claude,
                longContext: false,
                overlay: overlay
            ),
            1.5,
            "an override prices a model the built-in table does not know"
        )
        // And it outranks a built-in rate for a model that does have one.
        Harness.expectEqual(
            CostPricing.pricing(for: "claude-opus-5", provider: .claude, overlay: overlay)?.input,
            99,
            "an override outranks the built-in table"
        )

        // A one-hour cache write is billed at its own rate when the override states one, and at
        // twice input when it does not.
        let hourly = TokenTotals(cacheWrite: 1_000_000, cacheWrite1h: 1_000_000)
        Harness.expectEqual(
            CostPricing.cost(
                totals: hourly, model: "ox-tiered", provider: .codex,
                longContext: false, overlay: overlay
            ),
            3.5,
            "a stated one-hour rate is what bills"
        )
        Harness.expectEqual(
            CostPricing.cost(
                totals: hourly, model: "ox-tiered", provider: .codex,
                longContext: true, overlay: overlay
            ),
            7,
            "the long-context one-hour rate applies above the threshold"
        )
        Harness.expectEqual(
            CostPricing.cost(
                totals: hourly, model: "ox-alpha", provider: .claude,
                longContext: false, overlay: overlay
            ),
            3,
            "no stated one-hour rate falls back to twice input"
        )
        Harness.expect(
            CostPricing.isLongContext(
                totals: TokenTotals(input: 250_000), model: "ox-tiered",
                provider: .codex, overlay: overlay
            ),
            "an overridden threshold decides the tier"
        )

        // Saving nothing removes the file, handing control back to the lower layers.
        try? PricingOverlayStore.saveUserOverrides([:])
        Harness.expect(
            !FileManager.default.fileExists(atPath: url.path),
            "an empty override set deletes the file"
        )
        Harness.expectEqual(
            CostPricing.pricing(for: "claude-opus-5", provider: .claude)?.input,
            5,
            "the built-in rate returns once the override is gone"
        )
    }
}
