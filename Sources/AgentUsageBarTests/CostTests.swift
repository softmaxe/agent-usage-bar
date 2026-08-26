import AgentUsageBarCore
import Foundation

/// Cost-layer checks. The scan tests build synthetic transcripts in a temp directory and drive
/// the real scanner through `CostService`, with pricing pinned so nothing touches the network.
enum CostTests {
    static func run() async {
        Self.pricingLookup()
        Self.normalization()
        Self.longContextTiering()
        Self.overlayParsing()
        await Self.scanning()
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
        // gpt-5.6-sol charges double above 272k tokens in one request.
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
        Harness.expectEqual(baseCost, 5.0, "sol base input rate")
        Harness.expectEqual(longCost, 10.0, "sol long-context input rate")
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

    // MARK: - Scanning

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
        let codexLines = [
            #"{"type":"turn_context","timestamp":"\#(day)","payload":{"model":"gpt-5.6-sol"}}"#,
            #"{"type":"event_msg","timestamp":"\#(day)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200000,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":0}}}}"#,
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
        // 200k input tokens stays under sol's 272k long-context threshold, so the base rate applies.
        Harness.expectEqual(codex?.windowTokens, 200_000, "codex tokens scanned")
        Harness.expectEqual(codex?.windowCostUSD, 1.0, "codex cost at the sol base input rate")
        Harness.expectEqual(codex?.topModel, "gpt-5.6-sol", "codex top model")

        let claude = await service.refresh(.claude)
        // The duplicated message must not double the total.
        Harness.expectEqual(claude?.windowTokens, 1_000_000, "claude dedupes a replayed message")
        Harness.expectEqual(claude?.windowCostUSD, 5.0, "claude cost at the opus-5 input rate")

        // Scanning Claude must not evict Codex's rows: each scanner only knows its own roots, so
        // an unscoped prune would wipe the other provider every refresh.
        let codexAfter = await service.refresh(.codex)
        Harness.expectEqual(codexAfter?.windowTokens, 200_000, "codex survives a Claude scan")

        // Appending to a file must add to the totals rather than restate them.
        let appended = codexLines[1] + "\n"
        if let handle = try? FileHandle(forWritingTo: codexFile) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(appended.utf8))
            try? handle.close()
        }
        let codexGrown = await service.refresh(.codex)
        Harness.expectEqual(codexGrown?.windowTokens, 400_000, "appended turns are picked up incrementally")
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
