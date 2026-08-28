#if DEBUG
import AppKit
import SwiftUI

/// Every `--demo-*` flag opens the same window: a regular app with one hosting view, both held for
/// the life of the process so neither is collected while the run loop is still using them.
/// `DemoWindow` owns that scaffolding, which leaves each study file holding only the thing it is
/// actually studying — its view, its size and its title.
@MainActor
enum DemoWindow {
    private final class Delegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
    }

    private static var window: NSWindow?
    private static var delegate: Delegate?

    /// Centres `content` in its own window and runs the app. Returns only when the window closes,
    /// which ends the process.
    static func run(
        title: String,
        width: CGFloat,
        height: CGFloat,
        resizable: Bool = true,
        content: some View
    ) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = Delegate()
        app.delegate = delegate
        Self.delegate = delegate

        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable {
            styleMask.insert(.resizable)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.makeKeyAndOrderFront(nil)
        Self.window = window

        app.activate(ignoringOtherApps: true)
        app.run()
        exit(0)
    }
}
#endif
