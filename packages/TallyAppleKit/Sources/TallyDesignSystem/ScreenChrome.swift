import SwiftUI

/// ux-fp1 D01 (S1, systemic): on every scrolling screen, content scrolled past the top stayed
/// visible — blurred, not hidden — under the inline title, the toolbar buttons and the status bar,
/// even at rest. iOS 26's default scroll-edge effect (`.soft`) fades content under the bar instead
/// of hiding it; `.hard` was meant to fully occlude it, but round 1's Gate 2 review (D01 PARTIAL)
/// found large AX5 text still ghosting through at rest, and a navy hero scrolled under the bar
/// turning it into a grey-blue slab in light mode: `.hard` changes how much the scroll edge *fades*
/// content, but the bar's own Liquid Glass material still blends with whatever sits behind it. Round
/// 2 adds an explicit, opaque fill behind the bar (`toolbarBackground` + `toolbarBackgroundVisibility
/// (.visible, ...)`), so nothing can ever show through, on top of `.hard`'s edge behaviour.
///
/// Round 3 (R4, a round-2 regression): with the fill `.visible` at rest, iOS 26 drew it over the
/// tab roots' native large titles — "Dashboard", "Courses", "To-Do" and "Insights" left an empty
/// band on every leg (Gate 2 round 2, Audit tour run 37768388853), while every inline title
/// (Calendar once scrolled to today, Course detail, What-If, Settings) kept rendering on the same
/// opaque fill. So a large-title root asks for the fill `.automatic` instead: SwiftUI shows a
/// navigation bar's background only once content scrolls under it, so at rest the bar stays clear
/// and the large title shows (as in round 1, which had no fill), and once scrolled the title has
/// collapsed into the bar and the opaque `bgCanvas` fill is back — the state round 2 measured
/// clean for D01. See `tallyLargeTitleScreenChrome()`.
///
/// Apply to the outermost scrollable content of every `List`/`ScrollView` screen that uses the Tally
/// canvas/card palette (`Home/HomeShellView.swift`'s five tabs, `CourseDetail/CourseDetailView.swift`,
/// `CourseDetail/WhatIfSheet.swift`, `Subscription/PaywallView.swift`, the AX5 student switcher
/// sheet). A `Form`-based grouped sheet (Settings, Subscription, Family) uses `tallyFormScreenChrome()`
/// instead, below, so its bar matches its own grouped background rather than Tally's navy canvas.
public struct TallyScreenChrome: ViewModifier {
    /// `.visible` for an inline-title screen; `.automatic` for a large-title tab root (R4).
    private let barBackground: Visibility

    public init(hasLargeTitle: Bool = false) {
        barBackground = hasLargeTitle ? .automatic : .visible
    }

    public func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.hard, for: .top)
            .toolbarBackground(TallyColor.bgCanvas, for: .navigationBar)
            .toolbarBackgroundVisibility(barBackground, for: .navigationBar)
    }
}

extension View {
    /// D01: hides content scrolled under the top bar/status bar instead of showing it through a
    /// blur, with an opaque Tally-canvas fill behind the bar so nothing can ghost through even at
    /// the largest text sizes. See `TallyScreenChrome`.
    public func tallyScreenChrome() -> some View {
        modifier(TallyScreenChrome())
    }

    /// R4 (round 3): `tallyScreenChrome()` for a tab root with a native large title (Dashboard,
    /// Courses, Calendar, To-Do, Insights): the same opaque fill once content scrolls under the bar,
    /// none at rest, so the large title is never painted over. See `TallyScreenChrome`.
    public func tallyLargeTitleScreenChrome() -> some View {
        modifier(TallyScreenChrome(hasLargeTitle: true))
    }
}

/// ux-fp1 D01 round 2: the `Form`-based grouped sheets (Settings, Subscription, Family, and their
/// pushed/sheeted screens) ghosted content under the bar exactly like the List/ScrollView screens,
/// but they keep the system's own grouped background (never Tally's `bgCanvas`: D31's apply-list
/// explicitly excludes them, so FP-4's own dark-mode tint fix for these screens, D30, is not
/// pre-empted here).
///
/// Round 3: round 2's `toolbarBackgroundVisibility(.visible, ...)` with no colour left the bar a
/// translucent system material — 82 of 139 Form-sheet scroll captures still ghosted (75 at AX5).
/// The bar now gets an explicit opaque fill equal to the Form's own background, measured from
/// every Form-sheet capture of Audit tour run 37768388853 on all 8 legs (the margin beside the
/// rows, Settings, Subscription and Linked Students alike): exactly `#F2F2F7` light and `#1C1C1E`
/// dark — iOS's grouped background at the sheet's elevated level. Fixed values from the colour
/// scheme, not `Color(uiColor: .systemGroupedBackground)`: whether that UIKit colour resolves at
/// the sheet's elevated level (`#1C1C1E`) or the base level (`#000000`) once SwiftUI hands it to
/// the bar is not something this package can check without a device.
public struct TallyFormScreenChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.hard, for: .top)
            .toolbarBackground(colorScheme == .dark ? FormSheetBar.dark : FormSheetBar.light, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
    }
}

/// D01 round 3: the grouped `Form` sheets' measured background, light and dark (see
/// `TallyFormScreenChrome`).
enum FormSheetBar {
    /// `#F2F2F7`.
    static let light = Color(.sRGB, red: 0xF2 / 255.0, green: 0xF2 / 255.0, blue: 0xF7 / 255.0, opacity: 1)
    /// `#1C1C1E`.
    static let dark = Color(.sRGB, red: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1E / 255.0, opacity: 1)
}

extension View {
    /// D01 round 2: the grouped-`Form` sheets' own variant of `tallyScreenChrome()` — opaque, but
    /// in the Form's own background rather than Tally's navy canvas. See `TallyFormScreenChrome`.
    public func tallyFormScreenChrome() -> some View {
        modifier(TallyFormScreenChrome())
    }
}

/// ux-fp1 D27 (S3) + D31 (S2, dark): `List` screens (Courses, To-Do, Calendar, Course detail,
/// What-If) used the system's inset-grouped margin (20 pt) and the system's grouped colours, while
/// `ScrollView` screens (Dashboard, Insights, Paywall) used `TallySpacing.screenMargin` (16 pt) and
/// the Tally colour tokens — a 4 pt edge jump and, in dark, two different palettes on every tab
/// switch. One modifier unifies both: the Tally screen margin as the list's own content margin, and
/// the Tally canvas token behind the list.
///
/// Round 1 also set `.listRowBackground(TallyColor.bgCard)` here, on the `List` itself — Gate 2
/// (D31 PARTIAL) found the rows stayed the system's own grey (`#2C2C2E`): a list-row trait like
/// `.listRowBackground` only reaches a row when it's set on something that actually produces a row
/// (a `Section`, a `ForEach`, or a plain row view) — never on the `List` as a whole, which isn't
/// itself a row. `tallyRow()`, below, is the per-row form of the same token; every call site now
/// applies it directly to its rows/Sections instead.
public struct TallyListChrome: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, TallySpacing.screenMargin, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(TallyColor.bgCanvas)
    }
}

extension View {
    /// D27/D31: 16 pt content margins and the Tally canvas background on a `List`, in place of the
    /// system's 20 pt inset-grouped margin and grouped background. Pair with `tallyRow()` on every
    /// row/Section so the rows themselves pick up the Tally card colour too. See `TallyListChrome`.
    public func tallyList() -> some View {
        modifier(TallyListChrome())
    }
}

/// ux-fp1 D31 (S2, dark) round 2: the per-row half of `tallyList()`'s palette — `bg.card`, applied
/// directly to a row or to a `Section` (which reaches every row the Section contains), unlike
/// `.listRowBackground` set on the `List` itself, which reaches none of them. A row that draws its
/// own background (the Course Detail hero, `.listRowBackground(Color.clear)`) is left without this
/// modifier so its own colour keeps showing.
public struct TallyRow: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content.listRowBackground(TallyColor.bgCard)
    }
}

extension View {
    /// D31: the Tally card colour on one row, or on every row a `Section`/`ForEach` contains. See
    /// `TallyRow`.
    public func tallyRow() -> some View {
        modifier(TallyRow())
    }
}

/// ux-fp6 D33 (S3, dark): the navy hero shape (Dashboard, Course Detail), one place so every call
/// site gets the same fix. `bg.brand`'s new Dark appearance (a step lighter than Any) keeps the
/// hero off `bg.card`'s exact luminance (was 1.02:1), but the audit's own numbers for that lighter
/// navy (computed 1.25:1 off `bg.card`) still read as a close call, so dark also gets a 1 pt
/// `separator` hairline around the shape — light needs none (`bg.brand` there already reads far
/// darker than every light surface). No glow, as the fix list asks.
public struct TallyHeroBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func body(content: Content) -> some View {
        content
            .background(TallyColor.bgBrand, in: RoundedRectangle(cornerRadius: TallyRadius.hero, style: .continuous))
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: TallyRadius.hero, style: .continuous)
                        .stroke(TallyColor.separator)
                }
            }
    }
}

extension View {
    /// D33: `bg.brand` behind a continuous `TallyRadius.hero` shape, plus the dark-only hairline.
    /// See `TallyHeroBackground`.
    public func tallyHeroBackground() -> some View {
        modifier(TallyHeroBackground())
    }
}
