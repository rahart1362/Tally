import CoreGraphics

/// The 4 pt spacing grid and continuous corner radii (ux-ui.md §3.5).
/// Named so no view hand-writes a magic number (implementation brief rule:
/// "Name every magic number in configuration").
public enum TallySpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24
    public static let xxxl: CGFloat = 32

    /// Screen margins (§3.5: "Screen margins are 16 pt").
    public static let screenMargin: CGFloat = 16

    /// L10N-04 round 2 (gate-2 verdict L6): the floating tab bar's own footprint (its content
    /// height plus the home indicator's safe area) is not always reserved automatically for a
    /// screen that fully replaces a tab's content outside a `List`/`Form` (`LockedFeatureCard`):
    /// English's locked-tab card happened to end 91 pt above the smallest iPhone's bottom edge at
    /// AX5 (660-753 of an 844 pt screen) and read clean only because it is short enough to clear
    /// the tab bar by coincidence, while Spanish's longer body pushed "Ver planes" to 755-848 —
    /// inside the tab bar's own zone, so the tour's tap on it never opened the paywall. Any screen
    /// built the same way (content that can outgrow its viewport, with nothing already providing a
    /// tab-bar-safe bottom inset) should reserve this with `.safeAreaPadding(.bottom:)`, not a
    /// per-screen magic number. Rounded up a little past that 91 pt measurement for safety; confirm
    /// against the Audit tour's own captures, not assumed exact without a device.
    public static let tabBarClearance: CGFloat = 96
}

public enum TallyRadius {
    public static let hero: CGFloat = 26
    public static let card: CGFloat = 22
    public static let tile: CGFloat = 14
    public static let iconTile: CGFloat = 10
}
