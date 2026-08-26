import AppKit

/// One action row of the status menu, drawn by hand.
///
/// AppKit dismisses a menu the moment a standard item is picked, so Refresh used to cost the user
/// the card they were reading — and putting the menu back afterwards still blinks. A menu item
/// with a custom view owns its own mouse handling instead, so the row runs its action and leaves
/// the menu standing; the card then updates in place.
@MainActor
final class MenuActionRowView: NSView {
    private let title: String
    private let icon: NSImage?
    private let handler: () -> Void

    private var isHighlighted = false
    private var trackingArea: NSTrackingArea?

    static let rowHeight: CGFloat = 24
    /// The highlight is inset from the menu's edges, the way AppKit draws its own rows.
    private static let highlightInset: CGFloat = 5
    /// Where AppKit puts the image and the title of a standard item, measured off one. The two
    /// hand-drawn rows sit between two standard ones, so they follow those columns rather than
    /// deriving their own.
    private static let iconLeading: CGFloat = 16
    private static let titleLeading: CGFloat = 37
    private static let cornerRadius: CGFloat = 5

    init(
        width: CGFloat,
        title: String,
        icon: NSImage?,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.handler = handler
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))
        self.setAccessibilityRole(.menuItem)
        self.setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        let foreground: NSColor = self.isHighlighted ? .selectedMenuItemTextColor : .labelColor

        if self.isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(
                roundedRect: self.bounds.insetBy(dx: Self.highlightInset, dy: 0),
                xRadius: Self.cornerRadius,
                yRadius: Self.cornerRadius
            ).fill()
        }

        if let icon = self.icon {
            let rect = NSRect(
                x: Self.iconLeading,
                y: (self.bounds.height - icon.size.height) / 2,
                width: icon.size.width,
                height: icon.size.height
            )
            MenuIcons.tinted(icon, foreground).draw(in: rect)
        }

        let font = NSFont.menuFont(ofSize: 0)
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
        let titleSize = (self.title as NSString).size(withAttributes: titleAttributes)
        (self.title as NSString).draw(
            at: NSPoint(x: Self.titleLeading, y: (self.bounds.height - titleSize.height) / 2),
            withAttributes: titleAttributes
        )
    }

    // MARK: - Mouse

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { self.removeTrackingArea(trackingArea) }
        // `.activeInKeyWindow` would drop every event: a menu popup is never the key window.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with _: NSEvent) { self.setHighlighted(true) }

    override func mouseMoved(with _: NSEvent) { self.setHighlighted(true) }

    override func mouseExited(with _: NSEvent) { self.setHighlighted(false) }

    override func mouseDown(with _: NSEvent) {
        // Swallowed so the menu does not treat the press as a click-through; the action runs on
        // mouse up, which is where a menu row acts.
    }

    override func mouseUp(with event: NSEvent) {
        // A drag that started here and ended elsewhere is not a click on this row.
        guard self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return }
        self.handler()
    }

    private func setHighlighted(_ highlighted: Bool) {
        guard self.isHighlighted != highlighted else { return }
        self.isHighlighted = highlighted
        self.needsDisplay = true
    }
}
