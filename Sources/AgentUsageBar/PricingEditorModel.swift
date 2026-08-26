import AgentUsageBarCore
import Combine
import Foundation
import SwiftUI

enum PricingGroup: String, CaseIterable, Identifiable, Hashable {
    case claude = "Claude"
    case codex = "Codex"
    case others = "Others"

    var id: String { self.rawValue }

    static func classify(model: String) -> PricingGroup {
        let name = model.lowercased()
        if name.hasPrefix("claude-") { return .claude }
        if ["gpt-", "chatgpt-", "codex-", "o1", "o3", "o4"].contains(where: name.hasPrefix) {
            return .codex
        }
        return .others
    }
}

/// One editable row of the pricing table. Rates are USD per million tokens, matching how
/// providers publish them.
struct PricingRow: Identifiable, Equatable {
    let provider: Provider
    let group: PricingGroup
    let model: String
    /// True when the model appears in the local logs, which is what makes a row worth editing.
    let seenInLogs: Bool
    /// True when the built-in table or the models.dev catalog already prices this model.
    let hasDefault: Bool
    /// Total tokens seen in local logs. The settings list uses this to put active models first.
    let usageTokens: Int

    var input: String
    var output: String
    var cacheWrite: String
    var cacheRead: String

    var id: String { "\(self.provider.rawValue)|\(self.model)" }

    var isPriced: Bool {
        Double(self.input) != nil && Double(self.output) != nil
    }
}

/// Backs the pricing pane: loads the effective rates, tracks edits, and writes the override file.
@MainActor
final class PricingEditorModel: ObservableObject {
    @Published private(set) var rows: [PricingRow] = []
    @Published private(set) var isLoading = true
    @Published private(set) var saveError: String?
    @Published private(set) var hasUnsavedChanges = false

    private var originalRows: [String: PricingRow] = [:]
    /// Rates from the built-in table plus models.dev, i.e. what a row falls back to.
    private var defaults: [String: ModelPricing] = [:]
    private let costService: CostService
    /// Called after a successful save so the cards can re-price without waiting for a poll.
    var onSaved: (() -> Void)?

    init(costService: CostService) {
        self.costService = costService
    }

    func load() async {
        self.isLoading = true

        let overlay = await PricingOverlayStore.load()
        let overrides = PricingOverlayStore.loadUserOverrides()
        // The overlay minus the user layer is what a row would fall back to if its override
        // were removed, which is what the Reset button has to restore.
        let fallback = PricingOverlay(userOverrides: [:], modelsDev: overlay.modelsDev)

        var usageByProvider: [Provider: [ModelUsageTotal]] = [:]
        for provider in Provider.allCases {
            usageByProvider[provider] = await self.costService.knownModelUsage(provider: provider)
        }

        var built: [PricingRow] = []
        var defaults: [String: ModelPricing] = [:]

        for provider in Provider.allCases {
            let usage = usageByProvider[provider] ?? []
            let seen = usage.map(\.model)
            let builtIn = provider == .codex ? CostPricing.codex : CostPricing.claude

            // Normalized names, because that is the key everything else is looked up by.
            var names: [String] = []
            var included: Set<String> = []
            let providerOverrides = overrides.keys.filter { name in
                Self.provider(forOverride: name, usageByProvider: usageByProvider) == provider
            }
            for raw in seen + builtIn.keys.sorted() + providerOverrides.sorted() {
                let name = CostPricing.normalize(raw, provider: provider)
                guard !name.isEmpty, name != CostPricing.unknownModel, included.insert(name).inserted else {
                    continue
                }
                names.append(name)
            }

            let seenSet = Set(seen.map { CostPricing.normalize($0, provider: provider) })
            let usageTokens = Dictionary(uniqueKeysWithValues: usage.map {
                (CostPricing.normalize($0.model, provider: provider), $0.tokens)
            })

            for name in names {
                let fallbackPricing = CostPricing.pricing(for: name, provider: provider, overlay: fallback)
                // Only list a model under the provider that knows it, unless the logs saw it.
                guard seenSet.contains(name) || fallbackPricing != nil || overrides[name] != nil else {
                    continue
                }
                defaults["\(provider.rawValue)|\(name)"] = fallbackPricing

                let effective = overrides[name] ?? fallbackPricing
                built.append(PricingRow(
                    provider: provider,
                    group: PricingGroup.classify(model: name),
                    model: name,
                    seenInLogs: seenSet.contains(name),
                    hasDefault: fallbackPricing != nil,
                    usageTokens: usageTokens[name] ?? 0,
                    input: Self.text(effective?.input),
                    output: Self.text(effective?.output),
                    cacheWrite: Self.text(effective?.cacheWrite),
                    cacheRead: Self.text(effective?.cacheRead)
                ))
            }
        }

        // Provider sections stay stable; active models rise within their section by actual usage.
        built.sort { lhs, rhs in
            let lhsGroup = PricingGroup.allCases.firstIndex(of: lhs.group) ?? .max
            let rhsGroup = PricingGroup.allCases.firstIndex(of: rhs.group) ?? .max
            if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }
            if lhs.usageTokens != rhs.usageTokens { return lhs.usageTokens > rhs.usageTokens }
            if lhs.seenInLogs != rhs.seenInLogs { return lhs.seenInLogs }
            if lhs.seenInLogs, lhs.isPriced != rhs.isPriced { return !lhs.isPriced }
            return lhs.model < rhs.model
        }

        self.defaults = defaults
        self.rows = built
        self.originalRows = Dictionary(uniqueKeysWithValues: built.map { ($0.id, $0) })
        self.hasUnsavedChanges = false
        self.isLoading = false
    }

    func rows(in group: PricingGroup) -> [PricingRow] {
        self.rows.filter { $0.group == group }
    }

    func binding(for id: String, keyPath: WritableKeyPath<PricingRow, String>) -> Binding<String> {
        Binding(
            get: { self.rows.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let index = self.rows.firstIndex(where: { $0.id == id }) else { return }
                self.rows[index][keyPath: keyPath] = newValue
                self.hasUnsavedChanges = self.rows != Array(self.originalRows.values.sorted { $0.id < $1.id })
                    || self.rows.contains { row in self.originalRows[row.id] != row }
            }
        )
    }

    /// Restores a row to what it would be with no override.
    func reset(id: String) {
        guard let index = self.rows.firstIndex(where: { $0.id == id }) else { return }
        let fallback = self.defaults[id] ?? nil
        self.rows[index].input = Self.text(fallback?.input)
        self.rows[index].output = Self.text(fallback?.output)
        self.rows[index].cacheWrite = Self.text(fallback?.cacheWrite)
        self.rows[index].cacheRead = Self.text(fallback?.cacheRead)
        self.hasUnsavedChanges = true
    }

    func resetAll() {
        for row in self.rows { self.reset(id: row.id) }
    }

    /// Writes only the rows that differ from their fallback, so the override file stays small
    /// and future built-in updates still reach the untouched models.
    func save() async {
        var overrides: [String: ModelPricing] = [:]
        for row in self.rows {
            guard let input = Double(row.input.trimmingCharacters(in: .whitespaces)),
                  let output = Double(row.output.trimmingCharacters(in: .whitespaces)) else { continue }
            let pricing = ModelPricing(
                input: input,
                output: output,
                cacheWrite: Double(row.cacheWrite.trimmingCharacters(in: .whitespaces)),
                cacheRead: Double(row.cacheRead.trimmingCharacters(in: .whitespaces))
            )
            if let fallback = self.defaults[row.id] ?? nil, Self.matches(pricing, fallback) { continue }
            overrides[row.model] = pricing
        }

        do {
            try await self.costService.freezeCurrentPrices()
            try PricingOverlayStore.saveUserOverrides(overrides)
            await self.costService.invalidatePricing()
            self.saveError = nil
            self.hasUnsavedChanges = false
            self.originalRows = Dictionary(uniqueKeysWithValues: self.rows.map { ($0.id, $0) })
            self.onSaved?()
        } catch {
            self.saveError = error.localizedDescription
        }
    }

    /// Only the four editable rates are compared; long-context tiers are not editable here.
    private static func matches(_ lhs: ModelPricing, _ rhs: ModelPricing) -> Bool {
        lhs.input == rhs.input
            && lhs.output == rhs.output
            && lhs.cacheWrite == rhs.cacheWrite
            && lhs.cacheRead == rhs.cacheRead
    }

    private static func text(_ value: Double?) -> String {
        guard let value else { return "" }
        // Rates go to four decimals: cache reads run as low as $0.005 per million.
        return value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%g", value)
    }

    private static func provider(
        forOverride model: String,
        usageByProvider: [Provider: [ModelUsageTotal]]
    ) -> Provider {
        for provider in Provider.allCases where usageByProvider[provider]?.contains(where: {
            CostPricing.normalize($0.model, provider: provider)
                == CostPricing.normalize(model, provider: provider)
        }) == true {
            return provider
        }
        return PricingGroup.classify(model: model) == .claude ? .claude : .codex
    }
}
