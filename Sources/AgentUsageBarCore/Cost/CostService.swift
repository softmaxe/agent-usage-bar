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
    /// Readable without the actor so `CostUsageReader` can open the same file on a connection
    /// of its own rather than queueing behind a scan.
    public nonisolated let databaseURL: URL
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

    /// Refreshes the models.dev layer if it has gone stale and folds it into the cached
    /// overlay. Returns the new overlay only when the catalog actually moved, so a caller can
    /// tell whether it has anything to redraw.
    public func refreshPricingCatalog() async -> PricingOverlay? {
        guard let catalog = await PricingOverlayStore.refreshCatalogIfStale() else { return nil }
        let overlay = PricingOverlay(
            userOverrides: PricingOverlayStore.loadUserOverrides(),
            modelsDev: catalog
        )
        self.overlay = overlay
        return overlay
    }

    /// Replaces the cached price layers outright. The app reloads them from disk instead
    /// (`invalidatePricing`); this exists so tests can move prices without touching the network.
    public func usePricingOverlay(_ overlay: PricingOverlay) {
        self.overlay = overlay
    }

    /// Called immediately before an override file changes. Every log line already on disk is
    /// scanned and priced at the rates in force right now, and rows written by older app versions
    /// are frozen the same way. A stored cost is never recomputed, so the edit that follows can
    /// only reach usage recorded after it.
    public func freezeCurrentPrices() async throws {
        let cache = try self.openCache()
        let overlay = await self.currentOverlay()
        for provider in Provider.allCases {
            try cache.freezeLegacyPrices(provider: provider, overlay: overlay)
            do {
                switch provider {
                case .codex:
                    _ = try CodexLogScanner.scan(cache: cache, overlay: overlay, env: self.env)
                case .claude:
                    _ = try ClaudeLogScanner.scan(cache: cache, overlay: overlay, env: self.env)
                }
            } catch {
                // A provider whose logs cannot be read has nothing to freeze; the other one
                // still has to be sealed before the new rates land.
                Log.ui.error(
                    "\(provider.rawValue, privacy: .public) pre-edit scan failed: \(error.localizedDescription, privacy: .public)"
                )
            }
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
