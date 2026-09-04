// Adapted from CodexBar (MIT, © 2026 Peter Steinberger):
// Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift
//
// Rates are USD per million tokens here and divided down at lookup, which keeps the table
// readable against published price lists. Standard resolution uses the user override, then the
// models.dev overlay, then the built-in table. Fast resolution uses its own built-in table.

import Foundation

public struct ModelPricing: Sendable, Equatable {
    public let input: Double
    public let output: Double
    /// Five-minute cache write, which is the TTL the published tables quote.
    public let cacheWrite: Double?
    /// One-hour cache write. nil bills it at `oneHourCacheWriteMultiplier` times the input rate,
    /// which is the ratio Anthropic publishes instead of a column of its own.
    public let cacheWrite1h: Double?
    public let cacheRead: Double?
    /// Above this many tokens in one request the long-context rates apply.
    public let thresholdTokens: Int?
    public let inputAbove: Double?
    public let outputAbove: Double?
    public let cacheWriteAbove: Double?
    public let cacheWrite1hAbove: Double?
    public let cacheReadAbove: Double?

    public init(
        input: Double,
        output: Double,
        cacheWrite: Double? = nil,
        cacheWrite1h: Double? = nil,
        cacheRead: Double? = nil,
        thresholdTokens: Int? = nil,
        inputAbove: Double? = nil,
        outputAbove: Double? = nil,
        cacheWriteAbove: Double? = nil,
        cacheWrite1hAbove: Double? = nil,
        cacheReadAbove: Double? = nil
    ) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
        self.thresholdTokens = thresholdTokens
        self.inputAbove = inputAbove
        self.outputAbove = outputAbove
        self.cacheWriteAbove = cacheWriteAbove
        self.cacheWrite1hAbove = cacheWrite1hAbove
        self.cacheReadAbove = cacheReadAbove
    }

    /// Anthropic's published ratio between a one-hour cache write and the base input rate.
    /// Used only when no explicit one-hour rate is set.
    public static let oneHourCacheWriteMultiplier = 2.0

    /// The one-hour cache-write rate actually billed, derived from the input rate when the
    /// table (or the user's override) does not state one.
    public func cacheWrite1hRate(longContext: Bool) -> Double {
        let inputRate = (longContext ? self.inputAbove : nil) ?? self.input
        if let stated = (longContext ? self.cacheWrite1hAbove : nil) ?? self.cacheWrite1h { return stated }
        return inputRate * Self.oneHourCacheWriteMultiplier
    }

    /// Cost in USD for one bucket of tokens, at either the base or the long-context tier.
    public func cost(for totals: TokenTotals, longContext: Bool) -> Double {
        let million = 1_000_000.0
        let inputRate = (longContext ? self.inputAbove : nil) ?? self.input
        let outputRate = (longContext ? self.outputAbove : nil) ?? self.output
        // A model without its own cache rates bills cached tokens at the full input rate.
        let cacheWriteRate = (longContext ? self.cacheWriteAbove : nil) ?? self.cacheWrite ?? inputRate
        let cacheReadRate = (longContext ? self.cacheReadAbove : nil) ?? self.cacheRead ?? inputRate

        // Anthropic prices a one-hour cache write at twice the input rate, against 1.25x for the
        // five-minute default. The table's cache-write column is the five-minute rate, so unless
        // a one-hour rate is stated the longer TTL is derived the way Anthropic publishes it.
        let write1h = Double(min(totals.cacheWrite1h, totals.cacheWrite))
        let write5m = Double(totals.cacheWrite) - write1h

        return (Double(totals.input) * inputRate
            + Double(totals.output) * outputRate
            + write5m * cacheWriteRate
            + write1h * self.cacheWrite1hRate(longContext: longContext)
            + Double(totals.cacheRead) * cacheReadRate) / million
    }
}

public enum CostPricing {
    /// Model name recorded for tokens whose model could not be determined. Never priced.
    public static let unknownModel = "unknown"

    public enum CodexServiceTier: Sendable, Equatable {
        case standard
        case fast

        static func parse(_ raw: String?) -> Self {
            switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "priority", "fast": .fast
            default: .standard
            }
        }

        var isFast: Bool { self == .fast }
    }

    // MARK: - Built-in table

    /// Codex / OpenAI rates, USD per million tokens, checked against
    /// https://developers.openai.com/api/docs/pricing on 2026-08-26.
    ///
    /// OpenAI prices a separate cache write only for the gpt-5.6 family; for every other model
    /// it publishes a cached-input rate alone, so those cache writes fall through to the input
    /// rate, which is how they are billed.
    ///
    /// The models above the marker are the ones that page still prices. The rest were on it
    /// once and are kept so historical transcripts stay priced; a scan freezes each row's cost
    /// at the rates in force when it ran, so these only apply to logs scanned before the model
    /// went away.
    public static let codex: [String: ModelPricing] = [
        // -- Priced on the live page --------------------------------------------------------
        // Sol runs a promotion the page commits to "at least through November 21, 2026"; the
        // standard rates it replaces are $5 / $30 with a $6.25 cache write and $0.50 read.
        "gpt-5.6-sol": ModelPricing(
            input: 4, output: 20, cacheWrite: 5, cacheRead: 0.4,
            thresholdTokens: 272_000,
            inputAbove: 8, outputAbove: 30, cacheWriteAbove: 10, cacheReadAbove: 0.8
        ),
        "gpt-5.6-terra": ModelPricing(
            input: 2, output: 12, cacheWrite: 2.5, cacheRead: 0.2,
            thresholdTokens: 272_000,
            inputAbove: 4, outputAbove: 18, cacheWriteAbove: 5, cacheReadAbove: 0.4
        ),
        "gpt-5.6-luna": ModelPricing(
            input: 0.2, output: 1.2, cacheWrite: 0.25, cacheRead: 0.02,
            thresholdTokens: 272_000,
            inputAbove: 0.4, outputAbove: 1.8, cacheWriteAbove: 0.5, cacheReadAbove: 0.04
        ),
        // Daybreak security model, aliased daybreak-red-latest. No long-context tier.
        "gpt-5.6-cyber": ModelPricing(input: 12.5, output: 75, cacheWrite: 15.625, cacheRead: 1.25),
        // The page also lists a costlier Fast mode for this model; the transcripts carry no
        // mode, so the standard row is the one that can be applied.
        "gpt-5.3-codex": ModelPricing(input: 1.75, output: 14, cacheRead: 0.175),
        "codex-mini-latest": ModelPricing(input: 1.5, output: 6, cacheRead: 0.375),

        // -- Retired or no longer published; last known rates -------------------------------
        "gpt-5": ModelPricing(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5-codex": ModelPricing(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5-mini": ModelPricing(input: 0.25, output: 2, cacheRead: 0.025),
        "gpt-5-nano": ModelPricing(input: 0.05, output: 0.4, cacheRead: 0.005),
        "gpt-5-pro": ModelPricing(input: 15, output: 120),
        "gpt-5.1": ModelPricing(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5.1-codex": ModelPricing(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5.1-codex-max": ModelPricing(input: 1.25, output: 10, cacheRead: 0.125),
        "gpt-5.1-codex-mini": ModelPricing(input: 0.25, output: 2, cacheRead: 0.025),
        "gpt-5.2": ModelPricing(input: 1.75, output: 14, cacheRead: 0.175),
        "gpt-5.2-codex": ModelPricing(input: 1.75, output: 14, cacheRead: 0.175),
        "gpt-5.2-pro": ModelPricing(input: 21, output: 168),
        // Research preview: free while it lasts.
        "gpt-5.3-codex-spark": ModelPricing(input: 0, output: 0, cacheWrite: 0, cacheRead: 0),
        "gpt-5.4": ModelPricing(
            input: 2.5, output: 15, cacheRead: 0.25,
            thresholdTokens: 272_000, inputAbove: 5, outputAbove: 22.5, cacheReadAbove: 0.5
        ),
        "gpt-5.4-mini": ModelPricing(input: 0.75, output: 4.5, cacheRead: 0.075),
        "gpt-5.4-nano": ModelPricing(input: 0.2, output: 1.25, cacheRead: 0.02),
        "gpt-5.4-pro": ModelPricing(input: 30, output: 180),
        "gpt-5.5": ModelPricing(
            input: 5, output: 30, cacheRead: 0.5,
            thresholdTokens: 272_000, inputAbove: 10, outputAbove: 45, cacheReadAbove: 1
        ),
        "gpt-5.5-pro": ModelPricing(input: 30, output: 180),
    ]

    /// Fast Codex rates, USD per million tokens. Fast pricing is intentionally separate from
    /// the standard overlay so an unknown Fast model stays unpriced.
    public static let fastCodex: [String: ModelPricing] = [
        "gpt-5.6-sol": ModelPricing(
            input: 8, output: 40, cacheWrite: 10, cacheRead: 0.8,
            thresholdTokens: 272_000,
            inputAbove: 16, outputAbove: 60, cacheWriteAbove: 20, cacheReadAbove: 1.6
        ),
        "gpt-5.6-terra": ModelPricing(
            input: 4, output: 24, cacheWrite: 5, cacheRead: 0.4,
            thresholdTokens: 272_000,
            inputAbove: 8, outputAbove: 36, cacheWriteAbove: 10, cacheReadAbove: 0.8
        ),
        "gpt-5.6-luna": ModelPricing(
            input: 0.4, output: 2.4, cacheWrite: 0.5, cacheRead: 0.04,
            thresholdTokens: 272_000,
            inputAbove: 0.8, outputAbove: 3.6, cacheWriteAbove: 1, cacheReadAbove: 0.08
        ),
        "gpt-5.3-codex": ModelPricing(input: 3.5, output: 28, cacheRead: 0.35),
    ]

    /// Anthropic rates, USD per million tokens, checked against
    /// https://platform.claude.com/docs/en/about-claude/pricing on 2026-09-02.
    ///
    /// That page still states the family-wide ratios: a five-minute cache write is 1.25x the
    /// base input rate, a one-hour write 2x, and a cache read 0.1x, the last of which the 5.1
    /// pair breaks at 0.025x. The cache-write column below is the five-minute rate; the one-hour
    /// rate stays derived from input rather than repeated per model.
    ///
    /// No model on that page carries a long-context tier any more: 4.6 and later, and Mythos,
    /// bill their full 1M window at the standard rate, and Sonnet 4.5 is back to a 200K window
    /// priced flat.
    public static let claude: [String: ModelPricing] = [
        // Fable 5.1 and Mythos 5.1 price a cache read at 0.025x input, not the 0.1x every other
        // model bills, so the read rate here is a quarter of what the 5 pair below charges.
        "claude-fable-5-1": ModelPricing(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 0.25),
        "claude-mythos-5-1": ModelPricing(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 0.25),
        "claude-fable-5": ModelPricing(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 1),
        "claude-mythos-5": ModelPricing(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 1),
        "claude-opus-5": ModelPricing(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5),
        "claude-opus-4-8": ModelPricing(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5),
        "claude-opus-4-7": ModelPricing(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5),
        "claude-opus-4-6": ModelPricing(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5),
        "claude-opus-4-5": ModelPricing(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5),
        "claude-opus-4-1": ModelPricing(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5),
        "claude-opus-4": ModelPricing(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5),
        "claude-sonnet-5": ModelPricing(input: 2, output: 10, cacheWrite: 2.5, cacheRead: 0.2),
        "claude-sonnet-4-6": ModelPricing(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3),
        // Both carried a 2x tier above 200K while the 1M context beta ran; the price list no
        // longer publishes one, and Sonnet 4.5's window is back to 200K, so the tier could not
        // be reached even if it were still in force.
        "claude-sonnet-4-5": ModelPricing(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3),
        "claude-sonnet-4": ModelPricing(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3),
        "claude-haiku-4-5": ModelPricing(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.1),
        "claude-3-5-haiku": ModelPricing(input: 0.8, output: 4, cacheWrite: 1, cacheRead: 0.08),
    ]

    // MARK: - Normalization

    /// `openai/gpt-5.1-2026-01-01` -> `gpt-5.1`. Bare `gpt-5.6` is OpenAI's own alias for
    /// `gpt-5.6-sol`, which is how the model catalog lists it.
    public static func normalizeCodexModel(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        name = Self.strippingDateSuffix(name)
        if name == "gpt-5.6" { name = "gpt-5.6-sol" }
        return name
    }

    /// `anthropic.claude-opus-5-v1:0` -> `claude-opus-5`, `claude-opus-5-20260101` -> `claude-opus-5`.
    public static func normalizeClaudeModel(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["anthropic.", "anthropic/"] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        if let range = name.range(of: #"-v\d+:\d+$"#, options: .regularExpression) {
            name = String(name[..<range.lowerBound])
        }
        if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }
        return Self.strippingDateSuffix(name)
    }

    private static func strippingDateSuffix(_ name: String) -> String {
        if let range = name.range(of: #"-\d{8}$"#, options: .regularExpression) {
            return String(name[..<range.lowerBound])
        }
        if let range = name.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            return String(name[..<range.lowerBound])
        }
        return name
    }

    public static func normalize(_ raw: String, provider: Provider) -> String {
        switch provider {
        case .codex: self.normalizeCodexModel(raw)
        case .claude: self.normalizeClaudeModel(raw)
        }
    }

    // MARK: - Lookup

    /// Resolves a model's rates. `overlay` carries the user override and the models.dev catalog.
    public static func pricing(
        for rawModel: String,
        provider: Provider,
        overlay: PricingOverlay? = nil,
        codexServiceTier: CodexServiceTier = .standard
    ) -> ModelPricing? {
        let name = self.normalize(rawModel, provider: provider)
        guard name != Self.unknownModel, !name.isEmpty else { return nil }
        if provider == .codex, codexServiceTier == .fast { return Self.fastCodex[name] }
        if let override = overlay?.pricing(for: name) { return override }
        return provider == .codex ? Self.codex[name] : Self.claude[name]
    }

    /// Whether one request's input and cache tokens cross the model's long-context threshold.
    public static func isLongContext(
        totals: TokenTotals,
        model: String,
        provider: Provider,
        overlay: PricingOverlay? = nil,
        codexServiceTier: CodexServiceTier = .standard
    ) -> Bool {
        guard let threshold = self.pricing(
            for: model,
            provider: provider,
            overlay: overlay,
            codexServiceTier: codexServiceTier
        )?
            .thresholdTokens else { return false }
        let measured = totals.input + totals.cacheRead + totals.cacheWrite
        return measured > threshold
    }

    /// Cost in USD, or nil when the model has no price so its tokens stay uncounted.
    public static func cost(
        totals: TokenTotals,
        model: String,
        provider: Provider,
        longContext: Bool,
        overlay: PricingOverlay? = nil,
        codexServiceTier: CodexServiceTier = .standard
    ) -> Double? {
        guard let pricing = self.pricing(
            for: model,
            provider: provider,
            overlay: overlay,
            codexServiceTier: codexServiceTier
        ) else {
            return nil
        }
        return pricing.cost(for: totals, longContext: longContext)
    }
}
