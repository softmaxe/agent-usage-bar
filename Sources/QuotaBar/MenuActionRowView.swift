import AppKit

/// One action row of the status menu, drawn by hand.
///
/// AppKit dismisses a menu the moment a standard item is picked, so Refresh used to cost the user
/// the card they were reading — and putting the menu back afterwards still blinks. A menu item
/// with a custom view owns its own mouse handling instead, so the row runs its action and leaves
/// the menu standing; the card then updates in place.
@MainActor
final class MenuActionRowView: NSView {
    /// Mutable because the Refresh row rewrites itself into a countdown while the menu stands
    /// open; a row whose label is fixed at build time could not show one.
    var title: String {
        didSet {
            guard oldValue != self.title else { return }
            self.updateAccessibilityLabel()
            self.needsDisplay = true
        }
    }

    /// Optional text in the trailing shortcut column. It uses AppKit's secondary shortcut tint
    /// and is right aligned to the same edge as standard key equivalents.
    var trailingText: String? {
        didSet {
            guard oldValue != self.trailingText else { return }
            self.updateAccessibilityLabel()
            self.needsDisplay = true
        }
    }

    /// A disabled row draws greyed and swallows clicks, the way AppKit draws a disabled item.
    var isEnabled = true {
        didSet {
            guard oldValue != self.isEnabled else { return }
            self.setAccessibilityEnabled(self.isEnabled)
            if !self.isEnabled { self.isHighlighted = false }
            self.needsDisplay = true
        }
    }

    private let icon: NSImage?
    private let trailingIcon: NSImage?
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
    /// AppKit leaves about 17pt between a standard menu item's key equivalent and its edge.
    private static let trailingRightPadding: CGFloat = 17
    private static let cornerRadius: CGFloat = 5

    init(
        width: CGFloat,
        title: String,
        icon: NSImage?,
        trailingIcon: NSImage? = nil,
        trailingText: String? = nil,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.trailingText = trailingText
        self.icon = icon
        self.trailingIcon = trailingIcon
        self.handler = handler
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))
        self.setAccessibilityRole(.menuItem)
        self.updateAccessibilityLabel()
        self.setAccessibilityEnabled(true)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Drawing

    override func draw(_: NSRect) {
        let foreground: NSColor = if !self.isEnabled {
            .disabledControlTextColor
        } else if self.isHighlighted {
            .selectedMenuItemTextColor
        } else {
            .labelColor
        }
        let trailingForeground: NSColor = if !self.isEnabled {
            .disabledControlTextColor
        } else if self.isHighlighted {
            .selectedMenuItemTextColor
        } else {
            .secondaryLabelColor
        }

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

        if let trailingIcon {
            let rect = NSRect(
                x: self.trailingOrigin(for: trailingIcon.size.width),
                y: (self.bounds.height - trailingIcon.size.height) / 2,
                width: trailingIcon.size.width,
                height: trailingIcon.size.height
            )
            MenuIcons.tinted(trailingIcon, trailingForeground).draw(in: rect)
        }

        if let trailingText, !trailingText.isEmpty {
            let trailingAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: trailingForeground
            ]
            let trailingSize = (trailingText as NSString).size(withAttributes: trailingAttributes)
            (trailingText as NSString).draw(
                at: NSPoint(
                    x: self.trailingOrigin(for: trailingSize.width),
                    y: (self.bounds.height - trailingSize.height) / 2
                ),
                withAttributes: trailingAttributes
            )
        }
    }

    private func trailingOrigin(for contentWidth: CGFloat) -> CGFloat {
        self.bounds.width - Self.trailingRightPadding - contentWidth
    }

    private func updateAccessibilityLabel() {
        guard let trailingText, !trailingText.isEmpty else {
            self.setAccessibilityLabel(self.title)
            return
        }
        self.setAccessibilityLabel("\(self.title) \(trailingText)")
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
        guard self.isEnabled else { return }
        guard self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return }
        self.handler()
    }

    private func setHighlighted(_ highlighted: Bool) {
        guard self.isEnabled || !highlighted else { return }
        guard self.isHighlighted != highlighted else { return }
        self.isHighlighted = highlighted
        self.needsDisplay = true
    }
}
