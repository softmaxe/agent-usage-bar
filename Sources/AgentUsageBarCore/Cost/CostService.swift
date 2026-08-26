import Foundation

public struct ModelUsageTotal: Sendable, Equatable {
    public let model: String
    public let tokens: Int

    public init(model: String, tokens: Int) {
        self.model = model
        self.tokens = tokens
    }
}

/// Owns the scan cache and produces cost snapshots. An actor because the SQLite connection is
/// single-writer and scans run off the main thread.
public actor CostService {
    private var cache: CostCache?
    private var overlay: PricingOverlay?
    private let databaseURL: URL
    private let env: [String: String]

    /// `pricingOverlay` pins the price layers instead of loading them; tests use it to stay offline.
    public init(
        databaseURL: URL? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment,
        pricingOverlay: PricingOverlay? = nil
    ) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL
        self.env = env
        self.overlay = pricingOverlay
    }

    /// `~/Library/Caches/AgentUsageBar/cost-usage/cost-usage.sqlite`.
    public static var defaultDatabaseURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches
            .appendingPathComponent("AgentUsageBar/cost-usage", isDirectory: true)
            .appendingPathComponent("cost-usage.sqlite")
    }

    public func refresh(_ provider: Provider) async -> CostSnapshot? {
        do {
            let cache = try self.openCache()
            let overlay = await self.currentOverlay()
            try cache.freezeLegacyPrices(provider: provider, overlay: overlay)

            let started = Date()
            let touched: Int
            switch provider {
            case .codex:
                touched = try CodexLogScanner.scan(cache: cache, overlay: overlay, env: self.env)
            case .claude:
                touched = try ClaudeLogScanner.scan(cache: cache, overlay: overlay, env: self.env)
            }
            let elapsed = Date().timeIntervalSince(started)
            if touched > 0 {
                Log.ui.info(
                    "\(provider.rawValue, privacy: .public) cost scan: \(touched) files in \(String(format: "%.1f", elapsed))s"
                )
            }

            return try CostAggregator.snapshot(provider: provider, cache: cache)
        } catch {
            Log.ui.error(
                "\(provider.rawValue, privacy: .public) cost scan failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Models seen in local logs with their cumulative token totals, most-used first.
    public func knownModelUsage(provider: Provider) -> [ModelUsageTotal] {
        guard let cache = try? self.openCache(),
              let models = try? cache.distinctModelUsage(provider: provider) else { return [] }
        return models.compactMap { entry in
            guard entry.model != CostPricing.unknownModel else { return nil }
            return ModelUsageTotal(model: entry.model, tokens: entry.tokens)
        }
    }

    /// Drops the cached price layers so the next refresh picks up an edited override file.
    public func invalidatePricing() {
        self.overlay = nil
    }

    /// Called immediately before an override file changes, so rows created by older app versions
    /// are frozen with the old rates rather than the rates being saved.
    public func freezeCurrentPrices() async throws {
        let cache = try self.openCache()
        let overlay = await self.currentOverlay()
        for provider in Provider.allCases {
            try cache.freezeLegacyPrices(provider: provider, overlay: overlay)
        }
    }

    private func openCache() throws -> CostCache {
        if let cache = self.cache { return cache }
        let cache = try CostCache(path: self.databaseURL)
        self.cache = cache
        return cache
    }

    /// Loaded once per app run; the models.dev layer manages its own 24h disk TTL underneath.
    private func currentOverlay() async -> PricingOverlay {
        if let overlay = self.overlay { return overlay }
        let overlay = await PricingOverlayStore.load()
        self.overlay = overlay
        return overlay
    }
}
