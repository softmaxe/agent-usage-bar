import AgentUsageBarCore
import AppKit
import SwiftUI

/// Single settings window. The app is an accessory, so it has to activate itself to take focus.
@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let pricing: PricingEditorModel
    private var window: NSWindow?

    init(settings: SettingsStore, pricing: PricingEditorModel) {
        self.settings = settings
        self.pricing = pricing
    }

    func show() {
        if let window = self.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView(settings: self.settings, pricing: self.pricing)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "AgentUsageBar Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
