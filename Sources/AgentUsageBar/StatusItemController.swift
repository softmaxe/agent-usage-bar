import AgentUsageBarCore
import AppKit
import Combine
import SwiftUI

/// One `NSStatusItem` per provider. A provider with no credentials on this machine gets no
/// status item at all — an empty icon would be pure noise.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: UsageStore
    private var statusItems: [Provider: NSStatusItem] = [:]
    private var hostingViews: [Provider: NSHostingView<MenuCardView>] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(store: UsageStore) {
        self.store = store
        super.init()

        self.store.$states
            .receive(on: RunLoop.main)
            .sink { [weak self] states in self?.apply(states: states) }
            .store(in: &self.cancellables)

        self.store.$isRefreshing
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshOpenCards() }
            .store(in: &self.cancellables)
    }

    // MARK: - Status items

    private func apply(states: [Provider: ProviderState]) {
        // Keep a stable left-to-right order by rebuilding in declaration order.
        for provider in Provider.allCases {
            let state = states[provider]

            guard let state, !Self.isSignedOut(state) else {
                self.removeStatusItem(for: provider)
                continue
            }

            let item = self.statusItem(for: provider)
            item.button?.image = Self.icon(for: provider, state: state)
            item.button?.toolTip = Self.toolTip(for: provider, state: state)
            self.updateCard(for: provider, state: state)
        }
    }

    private static func isSignedOut(_ state: ProviderState) -> Bool {
        if case .signedOut = state { return true }
        return false
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

    private static func icon(for provider: Provider, state: ProviderState) -> NSImage {
        switch state {
        case .signedOut, .failed:
            // Stale styling dims the icon so a failing provider reads as "no fresh data".
            return IconRenderer.makeIcon(
                provider: provider,
                primaryRemaining: nil,
                weeklyRemaining: nil,
                stale: true
            )
        case let .loaded(snapshot):
            return IconRenderer.makeIcon(
                provider: provider,
                primaryRemaining: snapshot.session?.remainingPercent,
                weeklyRemaining: snapshot.weekly?.remainingPercent,
                stale: false
            )
        }
    }

    private static func toolTip(for provider: Provider, state: ProviderState) -> String {
        switch state {
        case let .signedOut(reason), let .failed(reason):
            "\(provider.displayName): \(reason)"
        case let .loaded(snapshot):
            [
                provider.displayName,
                snapshot.session.map { "session \(Formatters.percent($0.remainingPercent)) left" },
                snapshot.weekly.map { "weekly \(Formatters.percent($0.remainingPercent)) left" },
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        }
    }

    // MARK: - Menu

    private func makeMenu(for provider: Provider) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let cardItem = NSMenuItem()
        let hosting = NSHostingView(rootView: MenuCardView(
            provider: provider,
            state: .signedOut(""),
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

        // Settings lands in M3; the slot is here so the menu shape does not move later.
        let settings = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.isEnabled = false
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

    private func updateCard(for provider: Provider, state: ProviderState) {
        guard let hosting = self.hostingViews[provider] else { return }
        hosting.rootView = MenuCardView(
            provider: provider,
            state: state,
            isRefreshing: self.store.isRefreshing
        )
        // The card's height depends on how many windows the provider reported, so resize to fit.
        let height = hosting.fittingSize.height
        hosting.frame = NSRect(x: 0, y: 0, width: 280, height: height)
    }

    private func refreshOpenCards() {
        for (provider, state) in self.store.states {
            self.updateCard(for: provider, state: state)
        }
    }

    @objc private func refreshClicked() {
        self.store.refresh()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_: NSMenu) {
        // Opening the menu is an explicit "show me now", so force a refresh.
        self.store.refresh()
        self.refreshOpenCards()
    }
}
