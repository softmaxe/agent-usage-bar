/// Decides which provider status items belong in the menu bar.
public enum MenuBarVisibilityPolicy {
    /// Provider data is intentionally not an input: visibility follows the user's setting only.
    public static func visibleProviders(enabledProviders: Set<Provider>) -> Set<Provider> {
        enabledProviders
    }
}
