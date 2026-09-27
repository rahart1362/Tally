import SwiftUI

/// Design tokens (ux-ui.md §3.5). Each case names an asset-catalog colour set
/// in `Resources/Colors.xcassets`, with Any/Dark (and, where the review gives
/// distinct values, High Contrast) appearances. This is the shell-scope
/// subset used by the launch screen and the welcome screen (UX-WP-01/03);
/// the full token set and the categorical course palette land with the
/// screens that need them.
///
/// Colour is never the only signal (ux-ui.md §3.1 rule 4): every token here
/// is paired with text or an SF Symbol wherever it carries meaning.
public enum TallyColor {
    /// `bg.canvas` — page background. `UILaunchScreen`'s `LaunchBackground`
    /// colour set carries the same two values (Any `#F2F4F8`, Dark
    /// `#05080F`), so the first frame never flashes (ux-ui.md UX-02 fix).
    /// It has to be a *separate* colour set in the app's own asset catalog
    /// (`apps/TallyiOS/Tally/Assets.xcassets`), not this package's resource
    /// bundle: the system resolves `UILaunchScreen`'s `UIColorName` against
    /// the main bundle's compiled catalog before any app or SPM code runs,
    /// so it can't reach into a package's nested resource bundle.
    public static let bgCanvas = Color("bg.canvas", bundle: .module)

    /// `bg.card` — cards and list rows.
    public static let bgCard = Color("bg.card", bundle: .module)

    /// `bg.brand` — the welcome panel behind the T-mark.
    public static let bgBrand = Color("bg.brand", bundle: .module)

    /// `brand.gold` — ring, spark and the T-mark's arc. On navy only.
    public static let brandGold = Color("brand.gold", bundle: .module)

    /// `brand.cream` — the wordmark and T-mark fill on navy.
    public static let brandCream = Color("brand.cream", bundle: .module)

    /// `text.onHero` — primary text on the hero/brand panel.
    public static let textOnHero = Color("text.onHero", bundle: .module)

    /// `text.onHero2` — secondary text on the hero/brand panel.
    public static let textOnHero2 = Color("text.onHero2", bundle: .module)

    /// `text.primary` — body and titles.
    public static let textPrimary = Color("text.primary", bundle: .module)

    /// `text.secondary` — subtitles.
    public static let textSecondary = Color("text.secondary", bundle: .module)

    /// `accent` — tint, links, CTA fill.
    public static let accent = Color("accent", bundle: .module)

    /// `accent.onFill` — label colour on an accent-filled control.
    public static let accentOnFill = Color("accent.onFill", bundle: .module)

    /// `separator` — hairlines.
    public static let separator = Color("separator", bundle: .module)
}
