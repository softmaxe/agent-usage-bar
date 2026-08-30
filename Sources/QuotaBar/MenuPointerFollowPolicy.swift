import Foundation

/// Where the pointer belongs after the menu card changes height.
///
/// The card is as tall as the provider it shows — Codex adds a credits block Claude has no
/// equivalent for — and a menu hanging off the menu bar can only grow downwards. So the moment a
/// provider switch resizes the card, every row under it slides by the height difference: out from
/// under a pointer that never moved, and off a row still drawn highlighted, because a highlight
/// only clears on pointer movement. The next click then lands on the card and is swallowed, which
/// is what made a second "Switch provider" do nothing. Moving the pointer by the same amount keeps
/// it on the row it is pointing at.
enum MenuPointerFollowPolicy {
    /// Screen coordinates, AppKit's way up. nil leaves the pointer where it is.
    static func pointerDestination(
        pointer: CGPoint,
        menuFrameBefore: CGRect,
        cardBottomBefore: CGFloat,
        cardBottomAfter: CGFloat
    ) -> CGPoint? {
        let delta = cardBottomAfter - cardBottomBefore
        // Sub-point drift is not worth yanking the pointer for.
        guard abs(delta) >= 0.5 else { return nil }
        // The menu is measured before the resize on purpose: a card that shrank pulls the menu's
        // bottom edge up past a pointer that is still resting on a row.
        guard menuFrameBefore.contains(pointer) else { return nil }
        // Only what sits under the card moves with it. A pointer on the card itself, or on the
        // menu bar above it, keeps pointing at the same thing either way.
        guard pointer.y < cardBottomBefore else { return nil }
        return CGPoint(x: pointer.x, y: pointer.y + delta)
    }
}
