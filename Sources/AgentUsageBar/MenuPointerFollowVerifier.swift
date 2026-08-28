#if DEBUG
import Foundation

/// The Codex card is 62pt taller than the Claude card, so switching provider inside an open menu
/// slides every row under the card by that much. These are the cases that decide whether the
/// pointer follows them.
enum MenuPointerFollowVerifier {
    static func run() -> Never {
        // A menu hanging under the menu bar: 280 wide, card bottom 62pt above the rows it sits on.
        let menu = CGRect(x: 1_200, y: 410, width: 280, height: 669)
        let cardBottom: CGFloat = 522
        let onSwitchRow = CGPoint(x: 1_340, y: 499)
        var failures: [String] = []

        // Claude -> Codex: the card grows, so its bottom edge and the rows move down 62pt.
        let grew = MenuPointerFollowPolicy.pointerDestination(
            pointer: onSwitchRow,
            menuFrameBefore: menu,
            cardBottomBefore: cardBottom,
            cardBottomAfter: cardBottom - 62
        )
        if grew != CGPoint(x: onSwitchRow.x, y: onSwitchRow.y - 62) {
            failures.append("a card that grew 62pt left the pointer at \(String(describing: grew))")
        }

        // Codex -> Claude: the same move upwards, from a pointer the shrunk menu no longer covers.
        let shrank = MenuPointerFollowPolicy.pointerDestination(
            pointer: onSwitchRow,
            menuFrameBefore: menu,
            cardBottomBefore: cardBottom,
            cardBottomAfter: cardBottom + 62
        )
        if shrank != CGPoint(x: onSwitchRow.x, y: onSwitchRow.y + 62) {
            failures.append("a card that shrank 62pt left the pointer at \(String(describing: shrank))")
        }

        // Same provider, same height: nothing moved, so neither does the pointer.
        let unchanged = MenuPointerFollowPolicy.pointerDestination(
            pointer: onSwitchRow,
            menuFrameBefore: menu,
            cardBottomBefore: cardBottom,
            cardBottomAfter: cardBottom
        )
        if unchanged != nil {
            failures.append("an unchanged card moved the pointer to \(String(describing: unchanged))")
        }

        // A refresh landing while the pointer reads the card: the card grows away from it.
        let onCard = MenuPointerFollowPolicy.pointerDestination(
            pointer: CGPoint(x: 1_340, y: 700),
            menuFrameBefore: menu,
            cardBottomBefore: cardBottom,
            cardBottomAfter: cardBottom - 62
        )
        if onCard != nil {
            failures.append("a pointer on the card was moved to \(String(describing: onCard))")
        }

        // A refresh landing while the pointer is somewhere else entirely.
        let offMenu = MenuPointerFollowPolicy.pointerDestination(
            pointer: CGPoint(x: 400, y: 300),
            menuFrameBefore: menu,
            cardBottomBefore: cardBottom,
            cardBottomAfter: cardBottom - 62
        )
        if offMenu != nil {
            failures.append("a pointer outside the menu was moved to \(String(describing: offMenu))")
        }

        VerifierReport.finish(
            failures,
            label: "menu pointer follow verification",
            passed: "menu rows keep the pointer across a card resize, and nothing else moves it"
        )
    }
}
#endif
