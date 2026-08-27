import AgentUsageBarCore
import AppKit
import Combine
import SwiftUI

/// A single `NSStatusItem` showing one provider at a time. A left-click opens that provider's
/// card, a right-click switches to the next provider.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: UsageStore
    private let settings: SettingsStore
    private let settingsWindow: SettingsWindowController
    private let now: () -> Date
    private let openMenuClockInterval: TimeInterval
    private let refreshRowClockInterval: TimeInterval
    private var statusItem: NSStatusItem?
    private var hostingView: NSHostingView<MenuCardView>?
    /// Attached to the item only while a left-click is being handled, so a right-click can mean
    /// something other than "open the menu".
    private var menu: NSMenu?
    private var cancellables: Set<AnyCancellable> = []

    /// Only true between menuWillOpen and menuDidClose: a celebration is claimed when a card is
    /// there to play it, never while the menu is closed.
    private var isMenuOpen = false
    /// The resets the open menu is animating, and the token that replays them. Both are per
    /// provider, so switching providers mid-menu cannot replay the other one's animation.
    private var recoveries: [Provider: [QuotaWindowKind: QuotaRecoveryEvent]] = [:]
    private var celebrationTokens: [Provider: [QuotaWindowKind: Int]] = [:]
    /// "Updated 2m ago" and "Resets in 4h 53m" are strings built at render time, so an open menu
    /// needs its own clock; nothing else publishes between two scheduled refreshes.
    private var openMenuClock: Timer?
    /// The card's clock is too coarse for a per-second countdown, and re-rendering the whole card
    /// once a second to drive one label would be wasteful, so the Refresh row keeps its own.
    private var refreshRowClock: Timer?
    /// Owned by its menu item; held weakly so the row can be relabelled between rebuilt menus.
    private weak var refreshRow: MenuActionRowView?
    /// One autosave name for the one item, so switching providers leaves it where the user
    /// dragged it instead of moving the icon around.
    private static let autosaveName = "agentusagebar"
    /// The card and the action rows below it are one column.
    private static let cardWidth: CGFloat = 280

    init(
        store: UsageStore,
        settings: SettingsStore,
        pricing: PricingEditorModel,
        now: @escaping () -> Date = { Date() },
        openMenuClockInterval: TimeInterval = 15,
        refreshRowClockInterval: TimeInterval = 1
    ) {
        self.store = store
        self.settings = settings
        self.settingsWindow = SettingsWindowController(settings: settings, pricing: pricing)
        self.now = now
        self.openMenuClockInterval = openMenuClockInterval
        self.refreshRowClockInterval = refreshRowClockInterval
        super.init()

        // Saving pricing changes the numbers the card shows, so this one refresh forces past the
        // cooldown: the user is looking at the edit they just made.
        pricing.onSaved = { [weak store] in store?.refresh(force: true) }

        // SettingsStore is MainActor-isolated. Consume the emitted provider synchronously so
        // rapid switches cannot leave status-item work queued behind a newer selection.
        self.settings.$menuBarProvider
            .removeDuplicates()
            .sink { [weak self] provider in
                guard let self else { return }
                self.apply(provider: provider, displays: self.store.displays)
            }
            .store(in: &self.cancellables)

        // Cost scanning finishes well after the quota fetch, so both publishers drive a redraw.
        self.store.$displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] displays in self?.apply(displays: displays) }
            .store(in: &self.cancellables)

        self.store.$isRefreshing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshOpenCard() }
            .store(in: &self.cancellables)
    }

    // MARK: - Status item

    private func apply(provider: Provider? = nil, displays: [Provider: ProviderDisplay]) {
        let active = provider ?? self.settings.menuBarProvider
        let display = displays[active] ?? ProviderDisplay()
        let item = self.materializedStatusItem()
        item.button?.image = Self.icon(for: active, display: display)
        item.button?.toolTip = Self.toolTip(for: active, display: display)
        self.updateCard(provider: active, display: display)
    }

    private func materializedStatusItem() -> NSStatusItem {
        if let existing = self.statusItem { return existing }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        if let button = item.button {
            button.target = self
            button.action = #selector(self.statusItemClicked)
            // Without this the button only ever reports a left-click, and the right-click that
            // switches providers would never reach the handler.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.menu = self.makeMenu()
        self.statusItem = item
        return item
    }

#if DEBUG
    func debugStatusItemState() -> (
        exists: Bool,
        visible: Bool,
        attached: Bool,
        stableIdentity: Bool,
        provider: Provider
    ) {
        guard let item = self.statusItem else {
            return (false, false, false, false, self.settings.menuBarProvider)
        }
        return (
            true,
            item.isVisible,
            item.button?.window != nil,
            item.autosaveName == Self.autosaveName,
            self.settings.menuBarProvider
        )
    }

    func debugRefreshOpenCard() {
        self.refreshOpenCard()
    }

    func debugStartOpenMenuClock() {
        self.startOpenMenuClock()
    }

    func debugStopOpenMenuClock() {
        self.stopOpenMenuClock()
    }

    func debugStatusLine() -> String? {
        self.hostingView?.rootView.debugStatusLine
    }

    func debugRefreshRowState() -> (title: String, trailingText: String?, isEnabled: Bool)? {
        guard let row = self.refreshRow else { return nil }
        return (row.title, row.trailingText, row.isEnabled)
    }

    func debugClickRefreshRow() {
        guard let row = self.refreshRow, row.isEnabled else { return }
        self.refreshClicked()
    }

    func debugStartRefreshRowClock() {
        self.startRefreshRowClock()
    }

    func debugStopRefreshRowClock() {
        self.stopRefreshRowClock()
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
        parts.append("right-click to switch provider")
        return parts.joined(separator: " · ")
    }

    // MARK: - Clicks

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            // Control-click is the trackpad-only way to say the same thing.
            || event?.modifierFlags.contains(.control) == true
        if isSecondary {
            self.settings.advanceMenuBarProvider()
        } else {
            self.presentMenu()
        }
    }

    /// The menu lives off the item so the button keeps receiving clicks; attaching it for the
    /// duration of one click is how AppKit pops it up below the icon.
    private func presentMenu() {
        guard let item = self.statusItem, let menu = self.menu else { return }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let cardItem = NSMenuItem()
        let hosting = NSHostingView(rootView: MenuCardView(
            provider: self.settings.menuBarProvider,
            display: ProviderDisplay(),
            isRefreshing: false,
            now: self.now(),
            costChartLabelMode: self.settings.costChartLabelMode,
            onCostChartLabelModeChanged: { [weak self] mode in
                self?.settings.costChartLabelMode = mode
            }
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: Self.cardWidth, height: 200)
        cardItem.view = hosting
        self.hostingView = hosting
        menu.addItem(cardItem)

        menu.addItem(.separator())

        // Switch provider and Refresh act on the card the user is already looking at, so they are
        // custom rows: AppKit dismisses a menu the moment a standard item is picked, and putting
        // it back afterwards blinks. A custom row cannot carry a key equivalent — while a menu
        // tracks, AppKit matches ⌘-something against the items itself and skips any item with a
        // view — so these rows draw their own trailing shortcut content.
        menu.addItem(self.actionRow(
            title: "Switch provider",
            icon: MenuIcons.rightButtonMouse(),
            handler: { [weak self] in self?.settings.advanceMenuBarProvider() }
        ))

        // Subject to the cooldown, and says so: while it is running the row counts the wait down
        // and refuses clicks, rather than dropping them without a word.
        let refreshItem = NSMenuItem()
        let refreshRow = MenuActionRowView(
            width: Self.cardWidth,
            title: RefreshRowPolicy.idleTitle,
            icon: MenuIcons.symbol("arrow.clockwise"),
            trailingText: nil,
            handler: { [weak self] in self?.refreshClicked() }
        )
        refreshItem.view = refreshRow
        self.refreshRow = refreshRow
        menu.addItem(refreshItem)

        // These two leave the card behind anyway, so they stay standard items and keep working
        // key equivalents.
        let settings = NSMenuItem(
            title: "Settings",
            action: #selector(self.settingsClicked),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        settings.image = MenuIcons.symbol("gearshape")
        menu.addItem(settings)

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command]
        quit.image = MenuIcons.symbol("xmark.rectangle")
        menu.addItem(quit)

        return menu
    }

    private func actionRow(
        title: String,
        icon: NSImage?,
        trailingIcon: NSImage? = nil,
        trailingText: String? = nil,
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuActionRowView(
            width: Self.cardWidth,
            title: title,
            icon: icon,
            trailingIcon: trailingIcon,
            trailingText: trailingText,
            handler: handler
        )
        return item
    }

    private func updateCard(provider: Provider, display: ProviderDisplay) {
        guard let hosting = self.hostingView else { return }
        // A window can come back while the menu is already open, so this is claimed on every
        // update rather than only when the menu is opened.
        self.claimCelebrations(for: provider)
        let before = Self.openMenuGeometry(hosting)
        hosting.rootView = MenuCardView(
            provider: provider,
            display: display,
            isRefreshing: self.store.isRefreshing,
            recoveries: self.recoveries[provider] ?? [:],
            celebrationTokens: self.celebrationTokens[provider] ?? [:],
            now: self.now(),
            costChartLabelMode: self.settings.costChartLabelMode,
            onCostChartLabelModeChanged: { [weak self] mode in
                self?.settings.costChartLabelMode = mode
            }
        )
        // The card's height depends on how many windows the provider reported, so resize to fit.
        let height = hosting.fittingSize.height
        hosting.frame = NSRect(x: 0, y: 0, width: Self.cardWidth, height: height)
        Self.movePointerWithRows(from: before, hosting: hosting)
    }

    /// Takes whatever this provider has waiting and bumps its token, which is the value change
    /// the bars watch. Already-claimed windows keep the same token, so redrawing the open card
    /// does not restart an animation halfway through.
    private func claimCelebrations(for provider: Provider) {
        guard self.isMenuOpen else { return }
        let events = self.store.consumeCelebrations(for: provider)
        guard !events.isEmpty else { return }
        self.recoveries[provider, default: [:]].merge(events) { _, newest in newest }
        for kind in events.keys {
            self.celebrationTokens[provider, default: [:]][kind, default: 0] += 1
        }
    }

    /// The card's bottom edge and the menu's frame, both in screen coordinates. nil when no menu
    /// is on screen, which is every update the user is not looking at.
    private static func openMenuGeometry(
        _ hosting: NSHostingView<MenuCardView>
    ) -> (cardBottom: CGFloat, menuFrame: CGRect)? {
        guard let window = hosting.window else { return nil }
        let inWindow = hosting.convert(hosting.bounds, to: nil)
        let bottom = window.convertPoint(toScreen: NSPoint(x: inWindow.minX, y: inWindow.minY))
        return (bottom.y, window.frame)
    }

    /// Keeps the pointer on the row it is pointing at across a card resize. AppKit re-lays an open
    /// menu out as soon as the card's frame changes, so the rows below it have already moved.
    private static func movePointerWithRows(
        from before: (cardBottom: CGFloat, menuFrame: CGRect)?,
        hosting: NSHostingView<MenuCardView>
    ) {
        guard let before else { return }
        hosting.window?.contentView?.layoutSubtreeIfNeeded()
        guard let after = Self.openMenuGeometry(hosting),
              let destination = MenuPointerFollowPolicy.pointerDestination(
                  pointer: NSEvent.mouseLocation,
                  menuFrameBefore: before.menuFrame,
                  cardBottomBefore: before.cardBottom,
                  cardBottomAfter: after.cardBottom
              ),
              // Core Graphics measures from the top of the primary display, AppKit from its bottom.
              let primary = NSScreen.screens.first
        else { return }
        CGWarpMouseCursorPosition(CGPoint(
            x: destination.x,
            y: primary.frame.maxY - destination.y
        ))
    }

    private func refreshOpenCard() {
        let provider = self.settings.menuBarProvider
        self.updateCard(provider: provider, display: self.store.displays[provider] ?? ProviderDisplay())
        self.updateRefreshRow()
    }

    /// The row is already disabled for the whole cooldown, so this only ever reaches a store that
    /// will honour it; asking anyway keeps the store the single authority on the cooldown.
    private func refreshClicked() {
        self.store.refresh()
        self.updateRefreshRow()
    }

    private func updateRefreshRow() {
        guard let row = self.refreshRow else { return }
        let state = RefreshRowPolicy.state(
            cooldownRemaining: self.store.refreshCooldownRemaining(),
            isRefreshing: self.store.isRefreshing
        )
        row.title = state.title
        row.trailingText = state.trailingText
        row.isEnabled = state.isEnabled
    }

    @objc private func settingsClicked() {
        self.settingsWindow.show()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_: NSMenu) {
        // Opening the menu asks for a refresh; the store's cooldown decides. Within a minute of
        // any earlier refresh, poll or click alike, the open reuses that result.
        self.store.refresh()
        self.isMenuOpen = true
        // A celebration belongs to one viewing of the card. Whatever the last one played is over.
        self.recoveries = [:]
        self.refreshOpenCard()
        self.startOpenMenuClock()
        self.startRefreshRowClock()
    }

    func menuDidClose(_: NSMenu) {
        self.isMenuOpen = false
        self.stopOpenMenuClock()
        self.stopRefreshRowClock()
    }

    private func startOpenMenuClock() {
        self.stopOpenMenuClock()
        let timer = Timer(timeInterval: self.openMenuClockInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshOpenCard() }
        }
        // Menu tracking runs the run loop in its own mode, so the default mode would never fire.
        RunLoop.main.add(timer, forMode: .common)
        self.openMenuClock = timer
    }

    private func stopOpenMenuClock() {
        self.openMenuClock?.invalidate()
        self.openMenuClock = nil
    }

    private func startRefreshRowClock() {
        self.stopRefreshRowClock()
        let timer = Timer(timeInterval: self.refreshRowClockInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateRefreshRow() }
        }
        // Menu tracking runs the run loop in its own mode, so the default mode would never fire.
        RunLoop.main.add(timer, forMode: .common)
        self.refreshRowClock = timer
    }

    private func stopRefreshRowClock() {
        self.refreshRowClock?.invalidate()
        self.refreshRowClock = nil
    }
}
