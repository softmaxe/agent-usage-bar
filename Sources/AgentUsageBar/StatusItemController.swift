import AgentUsageBarCore
import AppKit
import Combine
import SwiftUI

/// One `NSStatusItem` per provider. A provider with no credentials on this machine gets no
/// status item at all — an empty icon would be pure noise.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: UsageStore
    private let settings: SettingsStore
    private let settingsWindow: SettingsWindowController
    private var statusItems: [Provider: NSStatusItem] = [:]
    private var hostingViews: [Provider: NSHostingView<MenuCardView>] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(store: UsageStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        self.settingsWindow = SettingsWindowController(settings: settings)
        super.init()

        self.settings.$enabledProviders
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.apply(displays: self.store.displays)
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

    private func apply(displays: [Provider: ProviderDisplay]) {
        // Keep a stable left-to-right order by rebuilding in declaration order.
        for provider in Provider.allCases {
            guard self.settings.isEnabled(provider),
                  let display = displays[provider],
                  !display.isSignedOut else {
                self.removeStatusItem(for: provider)
                continue
            }

            let item = self.statusItem(for: provider)
            item.button?.image = Self.icon(for: provider, display: display)
            item.button?.toolTip = Self.toolTip(for: provider, display: display)
            self.updateCard(for: provider, display: display)
        }
    }

    private func statusItem(for provider: Provider) -> NSStatusItem {
        if let existing = self.statusItems[provider] { return existing }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = self.makeMenu(for: provider)
        self.statusItems[provider] = item
        return item
    }

    private func removeStatusItem(for provider: Provider) {
        guard let item = self.statusItems.removeValue(forKey: provider) else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.hostingViews.removeValue(forKey: provider)
    }

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
        menu.addItem(refresh)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(self.settingsClicked),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        return menu
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
        // Opening the menu is an explicit "show me now", but it is debounced: the quota endpoints
        // rate-limit, and a menu can be opened many times a minute.
        self.store.refreshIfStale()
        self.refreshOpenCards()
    }
}
