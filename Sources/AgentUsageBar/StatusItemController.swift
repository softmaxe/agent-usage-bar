import AgentUsageBarCore
import AppKit
import Combine
import SwiftUI

/// One independently controlled `NSStatusItem` per provider.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: UsageStore
    private let settings: SettingsStore
    private let settingsWindow: SettingsWindowController
    private var statusItems: [Provider: NSStatusItem] = [:]
    private var hostingViews: [Provider: NSHostingView<MenuCardView>] = [:]
    private var cancellables: Set<AnyCancellable> = []

    /// "Updated 2m ago" and "Resets in 4h 53m" are strings built at render time, so an open menu
    /// needs its own clock; nothing else publishes between two scheduled refreshes.
    private var openMenuClock: Timer?
    private static let openMenuClockInterval: TimeInterval = 15

    init(store: UsageStore, settings: SettingsStore, pricing: PricingEditorModel) {
        self.store = store
        self.settings = settings
        self.settingsWindow = SettingsWindowController(settings: settings, pricing: pricing)
        super.init()

        pricing.onSaved = { [weak store] in store?.refresh() }

        // SettingsStore is MainActor-isolated. Consume the emitted set synchronously so rapid
        // toggles cannot leave status-item work queued behind a newer SwiftUI switch state.
        self.settings.$enabledProviders
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabledProviders in
                guard let self else { return }
                self.apply(enabledProviders: enabledProviders, displays: self.store.displays)
            }
            .store(in: &self.cancellables)

        // Cost scanning finishes well after the quota fetch, so both publishers drive a redraw.
        self.store.$displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] displays in self?.apply(displays: displays) }
            .store(in: &self.cancellables)

        self.store.$isRefreshing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshOpenCards() }
            .store(in: &self.cancellables)
    }

    // MARK: - Status items

    private func apply(
        enabledProviders: Set<Provider>? = nil,
        displays: [Provider: ProviderDisplay]
    ) {
        let visibleProviders = MenuBarVisibilityPolicy.visibleProviders(
            enabledProviders: enabledProviders ?? self.settings.enabledProviders
        )

        // Keep a stable left-to-right order by rebuilding in declaration order.
        for provider in Provider.allCases {
            guard visibleProviders.contains(provider) else {
                self.removeStatusItem(for: provider)
                continue
            }

            let display = displays[provider] ?? ProviderDisplay()
            let item = self.statusItem(for: provider)
            item.button?.image = Self.icon(for: provider, display: display)
            item.button?.toolTip = Self.toolTip(for: provider, display: display)
            self.updateCard(for: provider, display: display)
        }
    }

    private func statusItem(for provider: Provider) -> NSStatusItem {
        if let existing = self.statusItems[provider] { return existing }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName(for: provider)
        item.menu = self.makeMenu(for: provider)
        self.statusItems[provider] = item
        return item
    }

    private static func autosaveName(for provider: Provider) -> String {
        "agentusagebar-\(provider.rawValue)"
    }

    private func removeStatusItem(for provider: Provider) {
        guard let item = self.statusItems.removeValue(forKey: provider) else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.hostingViews.removeValue(forKey: provider)
    }

#if DEBUG
    func debugStatusItemState(
        for provider: Provider
    ) -> (exists: Bool, visible: Bool, attached: Bool, stableIdentity: Bool) {
        guard let item = self.statusItems[provider] else { return (false, false, false, false) }
        return (
            true,
            item.isVisible,
            item.button?.window != nil,
            item.autosaveName == Self.autosaveName(for: provider)
        )
    }
#endif

    /// A failed refresh keeps the last good percentages but dims them, so the icon still carries
    /// information instead of collapsing to an empty track.
    private static func icon(for provider: Provider, display: ProviderDisplay) -> NSImage {
        IconRenderer.makeIcon(
            provider: provider,
            primaryRemaining: display.snapshot?.session?.remainingPercent,
            weeklyRemaining: display.snapshot?.weekly?.remainingPercent,
            stale: display.isStale
        )
    }

    private static func toolTip(for provider: Provider, display: ProviderDisplay) -> String {
        var parts = [provider.displayName]
        if let snapshot = display.snapshot {
            if let session = snapshot.session {
                parts.append("session \(Formatters.percent(session.remainingPercent)) left")
            }
            if let weekly = snapshot.weekly {
                parts.append("weekly \(Formatters.percent(weekly.remainingPercent)) left")
            }
        }
        if let error = display.error { parts.append(error) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Menu

    private func makeMenu(for provider: Provider) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let cardItem = NSMenuItem()
        let hosting = NSHostingView(rootView: MenuCardView(
            provider: provider,
            display: ProviderDisplay(),
            isRefreshing: false
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 200)
        cardItem.view = hosting
        self.hostingViews[provider] = hosting
        menu.addItem(cardItem)

        menu.addItem(.separator())

        let refresh = NSMenuItem(
            title: "Refresh",
            action: #selector(self.refreshClicked),
            keyEquivalent: "r"
        )
        refresh.keyEquivalentModifierMask = [.command]
        refresh.target = self
        refresh.image = Self.menuIcon("arrow.clockwise")
        menu.addItem(refresh)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(self.settingsClicked),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        settings.image = Self.menuIcon("gearshape")
        menu.addItem(settings)

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        quit.image = Self.menuIcon("xmark.rectangle")
        menu.addItem(quit)

        return menu
    }

    /// Symbol names match CodexBar's menu actions so the three rows read the same way.
    private static func menuIcon(_ symbolName: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    private func updateCard(for provider: Provider, display: ProviderDisplay) {
        guard let hosting = self.hostingViews[provider] else { return }
        hosting.rootView = MenuCardView(
            provider: provider,
            display: display,
            isRefreshing: self.store.isRefreshing
        )
        // The card's height depends on how many windows the provider reported, so resize to fit.
        let height = hosting.fittingSize.height
        hosting.frame = NSRect(x: 0, y: 0, width: 280, height: height)
    }

    private func refreshOpenCards() {
        for (provider, display) in self.store.displays {
            self.updateCard(for: provider, display: display)
        }
    }

    @objc private func refreshClicked() {
        self.store.refresh()
    }

    @objc private func settingsClicked() {
        self.settingsWindow.show()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_: NSMenu) {
        // Opening the menu is an explicit "show me now", but it is debounced to the configured
        // cadence: the quota endpoints rate-limit, and a menu can be opened many times a minute.
        self.store.refreshIfStale()
        self.refreshOpenCards()
        self.startOpenMenuClock()
    }

    func menuDidClose(_: NSMenu) {
        self.stopOpenMenuClock()
    }

    private func startOpenMenuClock() {
        self.stopOpenMenuClock()
        let timer = Timer(timeInterval: Self.openMenuClockInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshOpenCards() }
        }
        // Menu tracking runs the run loop in its own mode, so the default mode would never fire.
        RunLoop.main.add(timer, forMode: .common)
        self.openMenuClock = timer
    }

    private func stopOpenMenuClock() {
        self.openMenuClock?.invalidate()
        self.openMenuClock = nil
    }
}
