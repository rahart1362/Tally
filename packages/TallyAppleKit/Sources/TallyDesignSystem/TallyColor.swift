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

    /// `bg.brand` — the welcome panel behind the T-mark, and every navy hero (Dashboard, Course
    /// Detail). ux-fp6 D33: Dark now has its own appearance, a step lighter (#0D2A55) than Any
    /// (#071A36), so the hero keeps a distinct luminance from `bg.card` in dark instead of
    /// matching it (1.02:1, Any has one appearance that is reused for Dark). Pair a hero shape
    /// with `tallyHeroBackground()`, which also adds the dark-only hairline D33 asks for.
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

    /// `accent` — tint, links. Dark flips to a light blue (#8DB4FF) for legibility on `bg.canvas`,
    /// which is why it is never the fill behind a white label or glyph (ux-fp6 D28): use
    /// `accentFill` for that.
    public static let accent = Color("accent", bundle: .module)

    /// `accent.fill` — the fill for a prominent, accent-coloured control (a filled button, the
    /// sample-data banner band, a swipe action): Any #1D4E9E, Dark a deeper #2E5FBF, so a white
    /// label/glyph on it stays ≥ 4.5:1 in both appearances. Added for ux-fp6 D28/D29: `accent`
    /// itself flips to a light blue in dark, which left the system's white button labels at
    /// 2.08–2.15:1. Pair with `accentOnFill` for the label colour.
    public static let accentFill = Color("accent.fill", bundle: .module)

    /// `accent.onFill` — label/glyph colour on an `accentFill`-filled control. White in both
    /// appearances: ux-fp6 D28 retired the old Dark override (a near-black #06142B, correct only
    /// for labelling the lighter `accent` itself in dark) now that this pairs with `accentFill`,
    /// which stays dark enough in both appearances for white to read.
    public static let accentOnFill = Color("accent.onFill", bundle: .module)

    /// `separator` — hairlines.
    public static let separator = Color("separator", bundle: .module)

    /// `warning` — a cautionary accent for text/icons, replacing the system `.orange` the audit
    /// flagged at 2.31:1 on white (D09) and in a hard-coded `.orange.opacity(0.16)` wash (D21).
    /// Any #8A5300 (~6.3:1 on white); Dark #FFB454 (~11.4:1 on `bg.canvas`'s dark value). Apply
    /// `.opacity(_:)` at the call site for a wash background (D21); for text/icons use it solid.
    public static let warning = Color("warning", bundle: .module)
}
