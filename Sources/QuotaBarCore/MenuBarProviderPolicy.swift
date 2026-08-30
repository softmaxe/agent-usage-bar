/// Which provider the single menu bar item shows, and where a right-click moves it.
public enum MenuBarProviderPolicy {
    /// The provider a right-click moves to, wrapping around the list. Provider data is
    /// intentionally not an input: a signed-out or not-yet-refreshed provider is still worth
    /// switching to, so its menu can explain itself instead of the item silently disappearing.
    public static func next(after provider: Provider) -> Provider {
        let all = Provider.allCases
        guard let index = all.firstIndex(of: provider) else { return all[0] }
        return all[(index + 1) % all.count]
    }
}
