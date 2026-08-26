// Adapted from CodexBar (MIT, © 2026 Peter Steinberger):
// Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift
//
// Rates are USD per million tokens here and divided down at lookup, which keeps the table
// readable against published price lists. Resolution order is user override, then the
// models.dev overlay, then this built-in table.

import Foundation

public struct ModelPricing: Sendable, Equatable {
    public let input: Double
    public let output: Double
    public let cacheWrite: Double?
    public let cacheRead: Double?
    /// Above this many tokens in one request the long-context rates apply.
    public let thresholdTokens: Int?
    public let inputAbove: Double?
    public let outputAbove: Double?
    public let cacheWriteAbove: Double?
    public let cacheReadAbove: Double?

    public init(
        input: Double,
        output: Double,
        cacheWrite: Double? = nil,
        cacheRead: Double? = nil,
        thresholdTokens: Int? = nil,
        inputAbove: Double? = nil,
        outputAbove: Double? = nil,
        cacheWriteAbove: Double? = nil,
        cacheReadAbove: Double? = nil
    ) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
        self.thresholdTokens = thresholdTokens
        self.inputAbove = inputAbove
        self.outputAbove = outputAbove
        self.cacheWriteAbove = cacheWriteAbove
        self.cacheReadAbove = cacheReadAbove
    }

    /// Anthropic's published ratio between a one-hour cache write and the base input rate.
    static let oneHourCacheWriteMultiplier = 2.0

    /// Cost in USD for one bucket of tokens, at either the base or the long-context tier.
    public func cost(for totals: TokenTotals, longContext: Bool) -> Double {
        let million = 1_000_000.0
        let inputRate = (longContext ? self.inputAbove : nil) ?? self.input
        let outputRate = (longContext ? self.outputAbove : nil) ?? self.output
        // A model without its own cache rates bills cached tokens at the full input rate.
        let cacheWriteRate = (longContext ? self.cacheWriteAbove : nil) ?? self.cacheWrite ?? inputRate
        let cacheReadRate = (longContext ? self.cacheReadAbove : nil) ?? self.cacheRead ?? inputRate

        // Anthropic prices a one-hour cache write at twice the input rate, against 1.25x for the
        // five-minute default. The table's cache-write column is the five-minute rate, so the
        // longer TTL is derived from the input rate the way Anthropic publishes it.
        let write1h = Double(min(totals.cacheWrite1h, totals.cacheWrite))
        let write5m = Double(totals.cacheWrite) - write1h

        return (Double(totals.input) * inputRate
            + Double(totals.output) * outputRate
            + write5m * cacheWriteRate
            + write1h * inputRate * Self.oneHourCacheWriteMultiplier
            + Double(totals.cacheRead) * cacheReadRate) / million
    }
}

public enum CostPricing {
    /// Model name recorded for tokens whose model could not be determined. Never priced.
    public static let unknownModel = "unknown"

    // MARK: - Built-in table

    /// Codex / OpenAI rates, USD per million tokens.
    public static let codex: [String: ModelPricing] = [
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
        "gpt-5.3-codex": ModelPricing(input: 1.75, output: 14, cacheRead: 0.175),
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
        "gpt-5.6-sol": ModelPricing(
            input: 5, output: 30, cacheWrite: 6.25, cacheRead: 0.5,
            thresholdTokens: 272_000,
            inputAbove: 10, outputAbove: 45, cacheWriteAbove: 12.5, cacheReadAbove: 1
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
    ]

    /// Anthropic rates, USD per million tokens. Cache write is 1.25x input and cache read 0.1x
    /// input across the family, which is how the derived columns below are set.
    ///
    /// `claude-opus-5`, `claude-sonnet-5` and `claude-mythos-5` are absent from CodexBar's table;
    /// their rates come from the published Anthropic price list.
    public static let claude: [String: ModelPricing] = [
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
        "claude-sonnet-4-5": ModelPricing(
            input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3,
            thresholdTokens: 200_000,
            inputAbove: 6, outputAbove: 22.5, cacheWriteAbove: 7.5, cacheReadAbove: 0.6
        ),
        "claude-sonnet-4": ModelPricing(
            input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3,
            thresholdTokens: 200_000,
            inputAbove: 6, outputAbove: 22.5, cacheWriteAbove: 7.5, cacheReadAbove: 0.6
        ),
        "claude-haiku-4-5": ModelPricing(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.1),
    ]

    // MARK: - Normalization

    /// `openai/gpt-5.1-2026-01-01` -> `gpt-5.1`, and the sol alias CodexBar carries.
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
        overlay: PricingOverlay? = nil
    ) -> ModelPricing? {
        let name = self.normalize(rawModel, provider: provider)
        guard name != Self.unknownModel, !name.isEmpty else { return nil }
        if let override = overlay?.pricing(for: name) { return override }
        return provider == .codex ? Self.codex[name] : Self.claude[name]
    }

    /// Whether one request's tokens cross the model's long-context threshold.
    /// Codex measures total input; Claude measures input plus both cache buckets.
    public static func isLongContext(
        totals: TokenTotals,
        model: String,
        provider: Provider,
        overlay: PricingOverlay? = nil
    ) -> Bool {
        guard let threshold = self.pricing(for: model, provider: provider, overlay: overlay)?
            .thresholdTokens else { return false }
        let measured = switch provider {
        case .codex: totals.input + totals.cacheRead + totals.cacheWrite
        case .claude: totals.input + totals.cacheRead + totals.cacheWrite
        }
        return measured > threshold
    }

    /// Cost in USD, or nil when the model has no price so its tokens stay uncounted.
    public static func cost(
        totals: TokenTotals,
        model: String,
        provider: Provider,
        longContext: Bool,
        overlay: PricingOverlay? = nil
    ) -> Double? {
        guard let pricing = self.pricing(for: model, provider: provider, overlay: overlay) else {
            return nil
        }
        return pricing.cost(for: totals, longContext: longContext)
    }
}
