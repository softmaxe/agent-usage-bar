// Adapted from CodexBar (MIT, © 2026 Peter Steinberger): Sources/CodexBar/MouseLocationReader.swift

import AppKit
import SwiftUI

/// Reports the pointer's position in local coordinates.
///
/// SwiftUI's `.onHover` gives no location, and `.help` tooltips never fire inside a menu at all:
/// an NSMenu popup is not a key window, so anything relying on key-window event routing is dead
/// there. An `.activeAlways` tracking area keeps working while the menu is up.
@MainActor
struct MouseLocationReader: NSViewRepresentable {
    let onMoved: (CGPoint?) -> Void

    func makeNSView(context _: Context) -> TrackingView {
        let view = TrackingView()
        view.onMoved = self.onMoved
        return view
    }

    func updateNSView(_ nsView: TrackingView, context _: Context) {
        nsView.onMoved = self.onMoved
    }

    final class TrackingView: NSView {
        var onMoved: ((CGPoint?) -> Void)?
        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            self.window?.acceptsMouseMovedEvents = true
            self.updateTrackingAreas()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { self.removeTrackingArea(trackingArea) }

            // `.activeInKeyWindow` would drop every event here, because a menu popup is never
            // the key window.
            let area = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self,
                userInfo: nil
            )
            self.addTrackingArea(area)
            self.trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            self.onMoved?(self.convert(event.locationInWindow, from: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            self.onMoved?(self.convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            self.onMoved?(nil)
        }
    }
}
