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
}

public enum TallyRadius {
    public static let hero: CGFloat = 26
    public static let card: CGFloat = 22
    public static let tile: CGFloat = 14
    public static let iconTile: CGFloat = 10
}
