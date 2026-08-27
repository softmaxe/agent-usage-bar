import AgentUsageBarCore
import Combine
import Foundation

/// Owns provider state and the refresh schedule. Fixed-interval polling plus manual refreshes
/// requested by status-item interactions, all funnelled through one cooldown.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var displays: [Provider: ProviderDisplay] = [:]
    @Published private(set) var isRefreshing = false

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var costTask: Task<Void, Never>?
    private let costService: CostService
    private let historyStore = UsageHistoryStore()
    private let recovery = QuotaRecoveryTracker()
    private let settings: SettingsStore
    private var settingsObserver: AnyCancellable?
    /// Every refresh claims this, whichever path asked for it, so the minute after any refresh
    /// stays quiet.
    private var cooldown = RefreshCooldownGate()
    private let clock: () -> TimeInterval

    init(
        settings: SettingsStore,
        costService: CostService,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.settings = settings
        self.costService = costService
        self.clock = clock
    }

    func start() {
        self.refresh()
        self.rescheduleTimer()
        self.settingsObserver = self.settings.$refreshFrequency
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rescheduleTimer() }
    }

    /// Rebuilt whenever the cadence changes; `.manual` leaves no timer at all.
    private func rescheduleTimer() {
        self.timer?.invalidate()
        self.timer = nil

        guard let interval = self.settings.refreshFrequency.seconds else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
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
        self.settingsObserver = nil
    }

    /// `force` is for refreshes that answer a change the user just made rather than the passage
    /// of time, where serving the pre-change numbers would look broken. It skips the cooldown but
    /// still starts it.
    func refresh(force: Bool = false) {
        // Coalesce: clicking the status item during a poll should not start a second round of
        // requests. Manual refreshes do not reschedule the independent polling timer.
        guard self.refreshTask == nil else { return }

        let now = self.clock()
        if force {
            self.cooldown.recordRefresh(at: now)
        } else if !self.cooldown.claimRefresh(at: now) {
            return
        }

        self.isRefreshing = true

        self.refreshTask = Task { [weak self, historyStore] in
            async let codex = CodexProvider.fetch()
            async let claude = ClaudeProvider.fetch()
            let results: [Provider: ProviderState] = await [.codex: codex, .claude: claude]

            // Sampling the weekly window builds the history the pace model regresses over.
            // CodexBar records only Codex here; the model is provider-agnostic, so both are.
            var histories: [Provider: UsageHistoryDataset] = [:]
            for (provider, state) in results {
                guard case let .loaded(snapshot) = state, let weekly = snapshot.weekly else { continue }
                if let dataset = await historyStore.record(provider: provider, window: weekly) {
                    histories[provider] = dataset
                }
            }

            await MainActor.run {
                guard let self else { return }
                for (provider, state) in results {
                    self.apply(state: state, to: provider)
                    Self.log(provider: provider, state: state)
                }
                for (provider, dataset) in histories {
                    self.displays[provider, default: ProviderDisplay()].history = dataset
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

    /// Seconds until the next refresh would actually run. The Refresh row counts this down
    /// instead of accepting clicks it would drop.
    func refreshCooldownRemaining() -> TimeInterval {
        self.cooldown.remaining(at: self.clock())
    }

    /// Window resets that have not been shown yet. Consuming them arms the animation, so only the
    /// card that actually shows it may ask.
    func consumeCelebrations(for provider: Provider) -> [QuotaWindowKind: QuotaRecoveryEvent] {
        self.recovery.consumePending(for: provider)
    }

#if DEBUG
    func debugSetDisplay(_ display: ProviderDisplay, for provider: Provider) {
        self.displays[provider] = display
    }

    /// Starts the cooldown without the network round trip a real refresh would make, so the menu
    /// wiring can be verified headlessly.
    func debugRecordRefresh(at time: TimeInterval) {
        self.cooldown.recordRefresh(at: time)
    }
#endif

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
            // Every reading, not just the ones the card is looking at: a window that runs dry has
            // to be noticed even when the menu has not been opened in hours.
            self.recovery.observe(provider: provider, snapshot: snapshot)
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
