// Adapted from CodexBar (MIT, © 2026 Peter Steinberger):
// Sources/CodexBarCore/Vendored/CostUsage/ModelsDevPricing.swift
//
// Two override layers sit above the built-in table: a JSON file the user edits by hand, and a
// cached copy of the models.dev catalog so new models get priced without an app update.

import Foundation

/// Snapshot of both override layers. Resolution order is user file, then models.dev.
public struct PricingOverlay: Sendable {
    let userOverrides: [String: ModelPricing]
    let modelsDev: [String: ModelPricing]

    public init(userOverrides: [String: ModelPricing] = [:], modelsDev: [String: ModelPricing] = [:]) {
        self.userOverrides = userOverrides
        self.modelsDev = modelsDev
    }

    func pricing(for normalizedModel: String) -> ModelPricing? {
        self.userOverrides[normalizedModel] ?? self.modelsDev[normalizedModel]
    }
}

public enum PricingOverlayStore {
    private static let catalogURL = URL(string: "https://models.dev/api.json")!
    private static let cacheTTL: TimeInterval = 24 * 60 * 60

    /// `~/Library/Application Support/AgentUsageBar/pricing-overrides.json`, hand-editable.
    public static var userOverridesURL: URL {
        Self.applicationSupportDirectory.appendingPathComponent("pricing-overrides.json")
    }

    /// `~/Library/Caches/AgentUsageBar/model-pricing/models-dev-v1.json`.
    static var catalogCacheURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches
            .appendingPathComponent("AgentUsageBar/model-pricing", isDirectory: true)
            .appendingPathComponent("models-dev-v1.json")
    }

    static var applicationSupportDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("AgentUsageBar", isDirectory: true)
    }

    /// Loads both layers, refreshing the models.dev cache when it has gone stale.
    /// A failed refresh keeps the previous cache rather than dropping prices on the floor.
    public static func load(transport: any HTTPTransport = URLSessionTransport()) async -> PricingOverlay {
        let overrides = Self.loadUserOverrides()
        var catalog = Self.loadCachedCatalog()

        if Self.cacheIsStale() {
            if let refreshed = await Self.fetchCatalog(transport: transport) {
                Self.writeCatalogCache(refreshed)
                catalog = Self.parseCatalog(refreshed) ?? catalog
            } else {
                Log.ui.info("models.dev refresh failed; keeping the cached price catalog")
            }
        }

        return PricingOverlay(userOverrides: overrides, modelsDev: catalog)
    }

    // MARK: - User overrides

    static func loadUserOverrides() -> [String: ModelPricing] {
        guard let data = try? Data(contentsOf: Self.userOverridesURL) else { return [:] }
        return Self.parseUserOverrides(data)
    }

    public static func parseUserOverrides(_ data: Data) -> [String: ModelPricing] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: ModelPricing] = [:]
        for (model, value) in root {
            guard let entry = value as? [String: Any],
                  let input = Self.double(entry["input"]),
                  let output = Self.double(entry["output"]) else { continue }
            result[model.lowercased()] = ModelPricing(
                input: input,
                output: output,
                cacheWrite: Self.double(entry["cacheWrite"]),
                cacheRead: Self.double(entry["cacheRead"]),
                thresholdTokens: (entry["thresholdTokens"] as? NSNumber)?.intValue,
                inputAbove: Self.double(entry["inputAbove"]),
                outputAbove: Self.double(entry["outputAbove"]),
                cacheWriteAbove: Self.double(entry["cacheWriteAbove"]),
                cacheReadAbove: Self.double(entry["cacheReadAbove"])
            )
        }
        return result
    }

    // MARK: - models.dev catalog

    private static func cacheIsStale() -> Bool {
        guard let attributes = try? FileManager.default
            .attributesOfItem(atPath: Self.catalogCacheURL.path),
            let modified = attributes[.modificationDate] as? Date else { return true }
        return Date().timeIntervalSince(modified) > Self.cacheTTL
    }

    private static func loadCachedCatalog() -> [String: ModelPricing] {
        guard let data = try? Data(contentsOf: Self.catalogCacheURL) else { return [:] }
        return Self.parseCatalog(data) ?? [:]
    }

    private static func fetchCatalog(transport: any HTTPTransport) async -> Data? {
        var request = URLRequest(url: Self.catalogURL, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await transport.send(request),
              response.statusCode == 200 else { return nil }
        // Only accept a payload that actually prices the two providers we care about; a
        // truncated or reshaped response must not wipe good cached prices.
        guard let parsed = Self.parseCatalog(data),
              parsed.keys.contains(where: { $0.hasPrefix("claude-") }),
              parsed.keys.contains(where: { $0.hasPrefix("gpt-") }) else { return nil }
        return data
    }

    private static func writeCatalogCache(_ data: Data) {
        let url = Self.catalogCacheURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
    }

    /// models.dev publishes USD per million tokens, keyed provider -> model.
    public static func parseCatalog(_ data: Data) -> [String: ModelPricing]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = root["providers"] as? [String: Any] else { return nil }

        var result: [String: ModelPricing] = [:]
        for (_, providerValue) in providers {
            guard let provider = providerValue as? [String: Any],
                  let models = provider["models"] as? [String: Any] else { continue }
            for (modelID, modelValue) in models {
                guard let model = modelValue as? [String: Any],
                      let cost = model["cost"] as? [String: Any],
                      let input = Self.double(cost["input"]),
                      let output = Self.double(cost["output"]) else { continue }

                let over200k = cost["context_over_200k"] as? [String: Any]
                let key = modelID.lowercased()
                // Keep the first entry for a model id; providers repeat popular models.
                guard result[key] == nil else { continue }
                result[key] = ModelPricing(
                    input: input,
                    output: output,
                    cacheWrite: Self.double(cost["cache_write"]),
                    cacheRead: Self.double(cost["cache_read"]),
                    thresholdTokens: over200k == nil ? nil : 200_000,
                    inputAbove: over200k.flatMap { Self.double($0["input"]) },
                    outputAbove: over200k.flatMap { Self.double($0["output"]) },
                    cacheWriteAbove: over200k.flatMap { Self.double($0["cache_write"]) },
                    cacheReadAbove: over200k.flatMap { Self.double($0["cache_read"]) }
                )
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
