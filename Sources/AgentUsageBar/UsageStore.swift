import AgentUsageBarCore
import Combine
import Foundation

/// Owns provider state and the refresh schedule. Fixed-interval polling plus a forced
/// refresh whenever a menu opens.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var displays: [Provider: ProviderDisplay] = [:]
    @Published private(set) var isRefreshing = false

    /// Fixed poll interval. Becomes a setting in M3. The quota endpoints are shared with the
    /// CLIs themselves and rate-limit aggressively, so this stays well clear of once a minute.
    var refreshInterval: TimeInterval = 5 * 60

    /// Opening a menu forces a refresh, but not more often than this.
    private static let menuRefreshDebounce: TimeInterval = 30
    private var lastRefreshStartedAt: Date?

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var costTask: Task<Void, Never>?
    private let costService = CostService()

    func start() {
        self.refresh()
        let timer = Timer(timeInterval: self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Common modes, so polling keeps running while a menu is open; the default mode alone
        // stops during menu tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        self.timer?.invalidate()
        self.timer = nil
        self.refreshTask?.cancel()
        self.costTask?.cancel()
    }

    /// Called when a menu opens. Debounced so repeatedly opening the menu cannot hammer the
    /// quota endpoints into a 429.
    func refreshIfStale() {
        if let last = self.lastRefreshStartedAt,
           Date().timeIntervalSince(last) < Self.menuRefreshDebounce {
            return
        }
        self.refresh()
    }

    func refresh() {
        // Coalesce: a menu opening during a poll should not start a second round of requests.
        guard self.refreshTask == nil else { return }
        self.isRefreshing = true
        self.lastRefreshStartedAt = Date()

        self.refreshTask = Task { [weak self] in
            async let codex = CodexProvider.fetch()
            async let claude = ClaudeProvider.fetch()
            let results: [Provider: ProviderState] = await [.codex: codex, .claude: claude]

            await MainActor.run {
                guard let self else { return }
                for (provider, state) in results {
                    self.apply(state: state, to: provider)
                    Self.log(provider: provider, state: state)
                }
                self.isRefreshing = false
                self.refreshTask = nil
            }
        }

        self.refreshCosts()
    }

    /// Log scanning runs on its own task: the first pass reads hundreds of megabytes and must not
    /// hold up the quota numbers, which are what the menu bar icon needs.
    private func refreshCosts() {
        guard self.costTask == nil else { return }

        self.costTask = Task { [weak self, costService] in
            var scanned: [Provider: CostSnapshot] = [:]
            for provider in Provider.allCases {
                if let snapshot = await costService.refresh(provider) {
                    scanned[provider] = snapshot
                }
            }
            await MainActor.run {
                guard let self else { return }
                for (provider, snapshot) in scanned {
                    self.displays[provider, default: ProviderDisplay()].cost = snapshot
                }
                self.costTask = nil
            }
        }
    }

    /// A failed refresh keeps whatever snapshot we already had: showing yesterday's numbers with
    /// an error line beats blanking a working card because one request was rate-limited.
    private func apply(state: ProviderState, to provider: Provider) {
        var display = self.displays[provider] ?? ProviderDisplay()
        switch state {
        case .signedOut:
            display.snapshot = nil
            display.error = nil
            display.isSignedOut = true
        case let .failed(reason):
            display.error = reason
            display.isSignedOut = false
        case let .loaded(snapshot):
            display.snapshot = snapshot
            display.error = nil
            display.isSignedOut = false
        }
        self.displays[provider] = display
    }

    private static func log(provider: Provider, state: ProviderState) {
        switch state {
        case let .signedOut(reason):
            Log.ui.info("\(provider.rawValue, privacy: .public) signed out: \(reason, privacy: .public)")
        case let .failed(reason):
            Log.ui.error("\(provider.rawValue, privacy: .public) refresh failed: \(reason, privacy: .public)")
        case let .loaded(snapshot):
            let session = snapshot.session?.remainingPercent ?? -1
            let weekly = snapshot.weekly?.remainingPercent ?? -1
            Log.ui.debug("\(provider.rawValue, privacy: .public) session=\(session) weekly=\(weekly)")
        }
    }
}
